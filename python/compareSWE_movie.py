"""
compareSWE_movie.py  –  Side-by-side SNODAS vs UCLA SR SWE movie
=================================================================

Left panel  : SNODAS SWE
Right panel : UCLA Snow Reanalysis SWE (ensemble mean)

Both panels share the same spatial extent, colour scale, date, and
static overlays (BRB outline, SNOTEL sites).

REQUIRES:
  - SNODAS_BRB_WY2021.pkl  (from Python getSNODAS_BRB equivalent)
  - UCLA_SWE_WY2021.pkl    (from Python getUCLA_SR_BRB equivalent)
    OR the corresponding .npz files
  - BRB_outline.shp  (in parent directory of this script)
  - plotSnowVar.py and makeSnowMovie.py in the same directory

USAGE:
    python compareSWE_movie.py

HP Marshall, Boise State University – SnowFusion Project, April 2026
"""

from __future__ import annotations

import copy
import datetime
import pathlib
import pickle
import sys
import time
import warnings

import imageio
import matplotlib.pyplot as plt
import numpy as np

# ---------------------------------------------------------------------------
# Sibling module path
# ---------------------------------------------------------------------------
_HERE = pathlib.Path(__file__).parent.resolve()
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from plotSnowVar import parula, _dates_as_date, _to_date
from mosaicUCLA_SR import mosaicUCLA_SR

try:
    import geopandas as gpd
    HAS_GPD = True
except ImportError:
    HAS_GPD = False

# ---------------------------------------------------------------------------
# Configuration  (edit here or adapt for CLI arguments)
# ---------------------------------------------------------------------------
DATA_ROOT    = pathlib.Path("/Users/hpmarshall/DATA_DRIVE/SnowFusion")
SCRIPT_DIR   = _HERE.parent          # parent of python/ = SnowFusion/
SNOTEL_SHP   = SCRIPT_DIR / "SNOTEL" / "IDDCO_2020_automated_sites.shp"

WY       = 2021
WY_START = datetime.date(WY - 1, 10, 1)   # Oct 1, 2020
WY_STR   = "WY2020_21"     # UCLA tile filename string

# UCLA tile coverage
LAT_TILES = [43, 44]
LON_TILES = [115, 116, 117]

# Movie settings
FPS       = 10    # default; overridden by user input at runtime

# Spatial extent
LATLIM = (43.0, 45.0)
LONLIM = (-117.0, -114.0)

# Shared SWE colour limits [m]
CLIM_SWE = (0.0, 1.5)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_data(path: pathlib.Path) -> dict:
    """Load a .pkl or .npz data dict."""
    if path.suffix == ".pkl":
        with open(path, "rb") as fh:
            d = pickle.load(fh)
        # unwrap if saved as {'Snodas': {...}} or {'UCLA': {...}}
        for key in ("Snodas", "UCLA"):
            if key in d and isinstance(d[key], dict):
                return d[key]
        return d
    elif path.suffix == ".npz":
        raw = np.load(path, allow_pickle=True)
        return {k: raw[k] for k in raw.files}
    else:
        raise ValueError(f"Unsupported file type: {path.suffix}")


def _fig_to_rgb(fig) -> np.ndarray:
    """Return figure canvas as H x W x 3 uint8 array."""
    fig.canvas.draw()
    buf = np.frombuffer(fig.canvas.buffer_rgba(), dtype=np.uint8)
    w, h = fig.canvas.get_width_height(physical=True)
    return buf.reshape(h, w, 4)[:, :, :3]


def _load_snotel(latlim, lonlim):
    try:
        from getSNOTEL_BRB import getSNOTEL_BRB
        return getSNOTEL_BRB(SNOTEL_SHP, lat_lim=latlim, lon_lim=lonlim)
    except Exception as e:
        warnings.warn(f"Could not load SNOTEL sites: {e}")
        return None


def _plot_panel(
    ax,
    lat_grid: np.ndarray, lon_grid: np.ndarray,
    S: np.ndarray,
    latlim: tuple, lonlim: tuple,
    clim: tuple,
    cmap,
    shp_gdf,
    snotel_data,
    panel_title: str,
) -> object:
    """
    Draw a single SWE panel onto *ax*.  Returns the imshow handle.
    """
    lat_min, lat_max = lat_grid.min(), lat_grid.max()
    lon_min, lon_max = lon_grid.min(), lon_grid.max()

    S_masked = np.ma.masked_where((S == 0) | ~np.isfinite(S), S)

    # Make masked (zero/NaN) pixels render as transparent white
    cmap_local = copy.copy(cmap)
    cmap_local.set_bad(color="white", alpha=0)

    im = ax.imshow(
        S_masked,
        extent=[lon_min, lon_max, lat_min, lat_max],
        origin="lower",
        aspect="equal",
        cmap=cmap_local,
        vmin=clim[0],
        vmax=clim[1],
        interpolation="nearest",
    )
    ax.set_facecolor("white")
    ax.set_xlim(lonlim)
    ax.set_ylim(latlim)
    ax.set_xlabel("Longitude", fontsize=11, fontweight="bold")
    ax.set_ylabel("Latitude", fontsize=11, fontweight="bold")
    ax.tick_params(labelsize=10)
    ax.set_aspect("equal")

    # colorbar
    fig = ax.figure
    cb = fig.colorbar(im, ax=ax, location="bottom", pad=0.10, fraction=0.04)
    cb.set_label("SWE [m]", fontsize=11, fontweight="bold")
    cb.ax.tick_params(labelsize=10)

    # shapefile
    if shp_gdf is not None:
        shp_gdf.boundary.plot(
            ax=ax, color=(0.2, 0.2, 0.2), linewidth=2.0, zorder=3
        )

    # SNOTEL
    if snotel_data and snotel_data.get("n_stations", 0) > 0:
        ax.plot(
            snotel_data["lon"], snotel_data["lat"],
            "r*", markersize=9, markeredgecolor="darkred", zorder=5,
        )

    ax.set_title(panel_title, fontsize=13, fontweight="bold")
    return im


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    # ---- prompt for FPS ---------------------------------------------------
    try:
        fps_input = input(f"Frames per second [default {FPS}]: ").strip()
        fps = int(fps_input) if fps_input else FPS
    except (ValueError, EOFError):
        fps = FPS
    print(f"Using {fps} fps")

    # ---- load SNODAS ------------------------------------------------------
    print(f"Loading SNODAS WY{WY} …")
    snodas_path = DATA_ROOT / "SNODAS" / f"SNODAS_BRB_WY{WY}.pkl"
    if not snodas_path.exists():
        # try .npz fallback
        snodas_path = snodas_path.with_suffix(".npz")
    if not snodas_path.exists():
        raise FileNotFoundError(
            f"SNODAS data not found at {snodas_path.with_suffix('.pkl')} "
            f"or {snodas_path.with_suffix('.npz')}"
        )
    snodas = _load_data(snodas_path)

    snodas_lat = np.asarray(snodas["lat"], dtype=float)
    snodas_lon = np.asarray(snodas["lon"], dtype=float)
    snodas_swe = snodas["SWE"]        # shape (nlat, nlon, ndays)

    # SNODAS lat north-to-south → flip to south-to-north
    if snodas_lat[0] > snodas_lat[-1]:
        snodas_lat = snodas_lat[::-1]
        snodas_swe = np.flip(snodas_swe, axis=0)

    # Prefer datestr (YYYY-MM-DD strings written by getSNODAS_BRB.py)
    if "datestr" in snodas:
        snodas_dates = [datetime.date.fromisoformat(str(s)) for s in snodas["datestr"]]
    else:
        snodas_dates = _dates_as_date(snodas["dates"])
    print(f"  SNODAS grid: {len(snodas_lat)} lat x {len(snodas_lon)} lon, "
          f"{len(snodas_dates)} days")

    # ---- load UCLA --------------------------------------------------------
    print("Loading UCLA SR …")
    ucla_data_dir = DATA_ROOT / "UCLA_SR"
    ucla_lat, ucla_lon, SWE_4d, _, _ = mosaicUCLA_SR(
        ucla_data_dir, WY_STR, LAT_TILES, LON_TILES
    )

    # Ensure lat ascending (south-to-north) for correct imshow orientation
    if ucla_lat[0] > ucla_lat[-1]:
        ucla_lat = ucla_lat[::-1]
        SWE_4d   = SWE_4d[::-1, ...]

    # Extract ensemble mean (axis 2, index 0) → shape (lat, lon, days)
    ucla_swe    = SWE_4d[:, :, 0, :].astype(float)
    n_days_ucla = ucla_swe.shape[2]
    ucla_dates  = [WY_START + datetime.timedelta(days=i) for i in range(n_days_ucla)]

    print(f"  UCLA grid: {len(ucla_lat)} lat x {len(ucla_lon)} lon, "
          f"{n_days_ucla} days")

    # ---- align dates -------------------------------------------------------
    snodas_date_set = set(snodas_dates)
    common_dates = sorted(d for d in ucla_dates if d in snodas_date_set)
    plot_dates   = common_dates
    n_frames     = len(plot_dates)
    print(f"Common dates: {len(common_dates)}  |  Frames to render: {n_frames}")

    # build index dicts for fast lookup
    sn_idx = {d: i for i, d in enumerate(snodas_dates)}
    uc_idx = {d: i for i, d in enumerate(ucla_dates)}

    # ---- load static overlays once ----------------------------------------
    shp_gdf = None
    shp_file = SCRIPT_DIR / "BRB_outline.shp"
    if shp_file.exists() and HAS_GPD:
        shp_gdf = gpd.read_file(shp_file)
        if shp_gdf.crs and shp_gdf.crs.to_epsg() != 4326:
            shp_gdf = shp_gdf.to_crs(epsg=4326)
    elif not HAS_GPD and shp_file.exists():
        warnings.warn("geopandas not available; shapefile overlay skipped.")

    snotel_data = _load_snotel(LATLIM, LONLIM)
    n_st = snotel_data.get("n_stations", 0) if snotel_data else 0
    print(f"SNOTEL sites in region: {n_st}")

    # ---- output path -------------------------------------------------------
    movies_dir = DATA_ROOT / "Movies"
    movies_dir.mkdir(parents=True, exist_ok=True)
    movie_file = movies_dir / f"SWE_comparison_SNODAS_UCLA_WY{WY}.mp4"

    # ---- set up figure and writer -----------------------------------------
    fig = plt.figure(figsize=(19.2, 7.2), facecolor="white")

    writer_kwargs = dict(fps=fps, quality=8, codec="libx264",
                         macro_block_size=None)

    print("Rendering frames …")
    t0 = time.time()

    with imageio.get_writer(str(movie_file), **writer_kwargs) as writer:
        for fi, d in enumerate(plot_dates):
            si = sn_idx[d]
            ui = uc_idx[d]

            S_sn = snodas_swe[:, :, si]
            S_uc = ucla_swe[:, :, ui]

            date_str = d.strftime("%d %b %Y")

            fig.clf()

            # ---- left: SNODAS ----
            ax1 = fig.add_subplot(1, 2, 1)
            _plot_panel(
                ax1,
                snodas_lat, snodas_lon, S_sn,
                LATLIM, LONLIM, CLIM_SWE, parula,
                shp_gdf, snotel_data,
                f"SNODAS SWE\n{date_str}",
            )

            # ---- right: UCLA SR ----
            ax2 = fig.add_subplot(1, 2, 2)
            _plot_panel(
                ax2,
                ucla_lat, ucla_lon, S_uc,
                LATLIM, LONLIM, CLIM_SWE, parula,
                shp_gdf, snotel_data,
                f"UCLA SR SWE (ensemble mean)\n{date_str}",
            )

            fig.suptitle(f"SWE Comparison  \u2014  WY{WY}",
                         fontsize=15, fontweight="bold")
            fig.tight_layout()

            # capture frame
            frame_rgb = _fig_to_rgb(fig)
            h, w = frame_rgb.shape[:2]
            if h % 2 != 0:
                frame_rgb = frame_rgb[:-1, :, :]
            if w % 2 != 0:
                frame_rgb = frame_rgb[:, :-1, :]
            writer.append_data(frame_rgb)

            if (fi + 1) % 50 == 0:
                print(f"  {fi + 1} / {n_frames} frames")

    elapsed = time.time() - t0
    print(f"Done: {n_frames} frames in {elapsed:.1f}s "
          f"({n_frames/elapsed:.1f} fps render)")
    plt.close(fig)
    print(f"Movie saved: {movie_file}")


if __name__ == "__main__":
    main()
