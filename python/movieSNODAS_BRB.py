"""
movieSNODAS_BRB.py  –  Water-year animation of SNODAS data for the BRB
=======================================================================

Creates an MP4 animation of a chosen SNODAS variable for the
Boise River Basin.  Equivalent to the MATLAB script movieSNODAS_BRB.m.

REQUIRES:
  - SNODAS_BRB_WY####.pkl  (or .npz) from getSNODAS_BRB.py
  - BRB_outline.shp  (in the parent directory of this script)

USAGE (edit the USER CONFIGURATION section below, then):
    python movieSNODAS_BRB.py

    or override from the command line:
    python movieSNODAS_BRB.py --wy 2024 --var SWE --fps 12

HP Marshall, Boise State University, April 2026
"""

from __future__ import annotations

import argparse
import pathlib
import pickle
import sys
import time
import warnings

import imageio
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import numpy as np

# ---------------------------------------------------------------------------
# Sibling module path
# ---------------------------------------------------------------------------
_HERE = pathlib.Path(__file__).parent.resolve()
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from plotSnowVar import parula, _dates_as_date

try:
    import geopandas as gpd
    HAS_GPD = True
except ImportError:
    HAS_GPD = False

# ---------------------------------------------------------------------------
# USER CONFIGURATION  (override with CLI flags or just edit here)
# ---------------------------------------------------------------------------
WY       = 2024
PLOT_VAR = "SWE"    # 'SWE','Depth','Precip','SnowPrecip','Tsnow',
                    # 'SublimationBS','Melt','Sublimation'
FPS      = 10

DATA_ROOT  = pathlib.Path("/Users/hpmarshall/DATA_DRIVE/SnowFusion")
SCRIPT_DIR = _HERE.parent   # parent of python/ = SnowFusion/

# ---------------------------------------------------------------------------
# Variable-specific parameters  (matches MATLAB switch block)
# ---------------------------------------------------------------------------
VAR_PARAMS: dict[str, dict] = {
    "SWE": dict(
        label="SWE [m]",
        clim=(0.0, 1.5),
        cmap=parula,
        title_base="Snow Water Equivalent",
    ),
    "Depth": dict(
        label="Snow Depth [m]",
        clim=(0.0, 3.0),
        cmap=parula,
        title_base="Snow Depth",
    ),
    "Precip": dict(
        label="Precipitation [mm]",
        clim=(0.0, 50.0),
        cmap=plt.cm.hot_r,          # flipud(hot)
        title_base="Precipitation",
    ),
    "SnowPrecip": dict(
        label="Snowfall [mm w.e.]",
        clim=(0.0, 50.0),
        cmap=plt.cm.hot_r,
        title_base="Snowfall",
    ),
    "Tsnow": dict(
        label="Temperature [K]",
        clim=(240.0, 273.0),
        cmap="cool",
        title_base="Snow Temperature",
    ),
    "Melt": dict(
        label="Melt [m]",
        clim=(0.0, 0.05),
        cmap="hot",
        title_base="Snow Melt",
    ),
    "Sublimation": dict(
        label="Sublimation [m]",
        clim=(0.0, 0.01),
        cmap="copper",
        title_base="Sublimation",
    ),
    "SublimationBS": dict(
        label="Blowing Snow Sublimation [m]",
        clim=(0.0, 0.005),
        cmap="copper",
        title_base="Blowing Snow Sublimation",
    ),
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_data(path: pathlib.Path) -> dict:
    if path.suffix == ".pkl":
        with open(path, "rb") as fh:
            d = pickle.load(fh)
        if "Snodas" in d and isinstance(d["Snodas"], dict):
            return d["Snodas"]
        return d
    elif path.suffix == ".npz":
        raw = np.load(path, allow_pickle=True)
        return {k: raw[k] for k in raw.files}
    raise ValueError(f"Unsupported file type: {path.suffix}")


def _fig_to_rgb(fig) -> np.ndarray:
    fig.canvas.draw()
    w, h = fig.canvas.get_width_height()
    buf = np.frombuffer(fig.canvas.tostring_rgb(), dtype=np.uint8)
    return buf.reshape(h, w, 3)


def _load_snotel():
    try:
        from getSNOTEL_BRB import get_snotel_brb
        return get_snotel_brb()
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run(wy: int, plot_var: str, fps: int) -> None:
    if plot_var not in VAR_PARAMS:
        raise ValueError(
            f"Unknown variable '{plot_var}'. "
            f"Choose from: {', '.join(VAR_PARAMS)}"
        )
    params = VAR_PARAMS[plot_var]

    # ---- load data --------------------------------------------------------
    data_dir  = DATA_ROOT / "SNODAS"
    mat_file  = data_dir / f"SNODAS_BRB_WY{wy}.pkl"
    if not mat_file.exists():
        mat_file = mat_file.with_suffix(".npz")
    if not mat_file.exists():
        raise FileNotFoundError(
            f"Data file not found: {data_dir / f'SNODAS_BRB_WY{wy}.pkl'}\n"
            "Run getSNODAS_BRB.py first."
        )

    print(f"Loading {mat_file} …")
    snodas = _load_data(mat_file)

    lat    = np.asarray(snodas["lat"], dtype=float)
    lon    = np.asarray(snodas["lon"], dtype=float)
    dates  = _dates_as_date(snodas["dates"])
    n_days = len(dates)

    var_3d = snodas[plot_var]   # (nlat, nlon, ndays)

    # SNODAS lat may be north-to-south – flip to south-to-north
    if lat[0] > lat[-1]:
        lat    = lat[::-1]
        var_3d = np.flip(var_3d, axis=0)

    lat_min, lat_max = lat.min(), lat.max()
    lon_min, lon_max = lon.min(), lon.max()

    # ---- load shapefile ---------------------------------------------------
    shp_gdf = None
    shp_file = SCRIPT_DIR / "BRB_outline.shp"
    if shp_file.exists() and HAS_GPD:
        shp_gdf = gpd.read_file(shp_file)
        if shp_gdf.crs and shp_gdf.crs.to_epsg() != 4326:
            shp_gdf = shp_gdf.to_crs(epsg=4326)
    elif shp_file.exists() and not HAS_GPD:
        warnings.warn("geopandas not available; shapefile overlay skipped.")

    # ---- load SNOTEL ------------------------------------------------------
    snotel_data = _load_snotel()
    if snotel_data:
        print(f"Loaded {snotel_data.get('n_stations', 0)} SNOTEL stations")

    # ---- set up figure (persistent across frames) -------------------------
    fig = plt.figure(figsize=(10, 8), facecolor="white")
    ax  = fig.add_subplot(111)
    ax.set_facecolor("white")

    # First frame
    S0 = var_3d[:, :, 0].astype(float)
    S0_masked = np.ma.masked_where((S0 == 0) | ~np.isfinite(S0), S0)

    im = ax.imshow(
        S0_masked,
        extent=[lon_min, lon_max, lat_min, lat_max],
        origin="lower",
        aspect="equal",
        cmap=params["cmap"],
        vmin=params["clim"][0],
        vmax=params["clim"][1],
        interpolation="nearest",
    )

    ax.set_xlim(lon_min, lon_max)
    ax.set_ylim(lat_min, lat_max)
    ax.set_xlabel("Longitude", fontsize=12, fontweight="bold")
    ax.set_ylabel("Latitude",  fontsize=12, fontweight="bold")
    ax.tick_params(labelsize=11)
    ax.set_aspect("equal")

    cb = fig.colorbar(im, ax=ax, location="bottom", pad=0.08, fraction=0.04)
    cb.set_label(params["label"], fontsize=12, fontweight="bold")
    cb.ax.tick_params(labelsize=11)

    if shp_gdf is not None:
        shp_gdf.boundary.plot(
            ax=ax, color=(0.3, 0.3, 0.3), linewidth=2.5, zorder=3
        )

    if snotel_data and snotel_data.get("n_stations", 0) > 0:
        ax.plot(
            snotel_data["lon"], snotel_data["lat"],
            "r*", markersize=12, markeredgecolor="darkred", zorder=5,
        )

    htitle = ax.set_title(
        f"SNODAS {params['title_base']} – BRB – {dates[0]}",
        fontsize=16, fontweight="bold",
    )
    fig.tight_layout()

    # ---- output path ------------------------------------------------------
    movies_dir = DATA_ROOT / "Movies"
    movies_dir.mkdir(parents=True, exist_ok=True)
    video_file = movies_dir / f"SNODAS_BRB_{plot_var}_WY{wy}.mp4"

    writer_kwargs = dict(fps=fps, quality=8, codec="libx264",
                         macro_block_size=None)

    print(f"Creating animation: {video_file}")
    print(f"  {n_days} frames at {fps} fps = {n_days/fps:.1f} seconds")

    t0 = time.time()
    with imageio.get_writer(str(video_file), **writer_kwargs) as writer:
        for d_idx in range(n_days):
            S = var_3d[:, :, d_idx].astype(float)
            S_masked = np.ma.masked_where((S == 0) | ~np.isfinite(S), S)

            # update existing image data for efficiency
            im.set_data(S_masked)
            htitle.set_text(
                f"SNODAS {params['title_base']} – BRB – {dates[d_idx]}"
            )

            fig.canvas.draw()
            frame_rgb = _fig_to_rgb(fig)
            h, w = frame_rgb.shape[:2]
            if h % 2 != 0:
                frame_rgb = frame_rgb[:-1, :, :]
            if w % 2 != 0:
                frame_rgb = frame_rgb[:, :-1, :]
            writer.append_data(frame_rgb)

            if (d_idx + 1) % 30 == 0:
                print(f"  Frame {d_idx + 1}/{n_days} ({dates[d_idx]})")

    elapsed = time.time() - t0
    plt.close(fig)
    print(f"\nVideo saved: {video_file}")
    print(f"Duration: {n_days/fps:.1f} seconds at {fps} fps  "
          f"(render time: {elapsed:.1f}s)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Create a SNODAS BRB water-year animation."
    )
    parser.add_argument(
        "--wy", type=int, default=WY,
        help=f"Water year (default: {WY})",
    )
    parser.add_argument(
        "--var", default=PLOT_VAR,
        choices=list(VAR_PARAMS.keys()),
        help=f"Variable to animate (default: {PLOT_VAR})",
    )
    parser.add_argument(
        "--fps", type=int, default=FPS,
        help=f"Frames per second (default: {FPS})",
    )
    args = parser.parse_args()

    run(args.wy, args.var, args.fps)
