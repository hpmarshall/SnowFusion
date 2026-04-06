"""
makeSnowMovie.py  –  Create an MP4 movie of a snow variable over a water year.

USAGE (as a function):
    make_snow_movie(data_struct, var_name, movie_file)
    make_snow_movie(data_struct, var_name, movie_file,
                   fps=10, skip_days=1, shapefile='BRB_outline.shp',
                   latlim=(43.0, 45.0), lonlim=(-117.0, -114.0),
                   snotel=True)

EXAMPLE:
    import pickle
    with open('SNODAS_WY2020.pkl', 'rb') as f:
        data = pickle.load(f)
    make_snow_movie(data, 'SWE', 'SNODAS_SWE_WY2020.mp4',
                    shapefile='BRB_outline.shp', fps=12)

HP Marshall, Boise State University – SnowFusion Project
"""

from __future__ import annotations

import datetime
import pathlib
import sys
import time
import warnings
from typing import Sequence

import imageio
import matplotlib.pyplot as plt
import numpy as np

# Optional geopandas for shapefile support
try:
    import geopandas as gpd
    HAS_GPD = True
except ImportError:
    HAS_GPD = False

# Re-use helpers from plotSnowVar (same directory)
_HERE = pathlib.Path(__file__).parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from plotSnowVar import get_var_defaults, _to_date, _dates_as_date, parula

# ---------------------------------------------------------------------------
# SNOTEL helper
# ---------------------------------------------------------------------------

def _load_snotel(latlim, lonlim):
    """Try to load SNOTEL sites; return dict or None on failure."""
    try:
        from getSNOTEL_BRB import getSNOTEL_BRB
        shp_path = _HERE.parent / "SNOTEL" / "IDDCO_2020_automated_sites.shp"
        return getSNOTEL_BRB(shp_path, lat_lim=latlim, lon_lim=lonlim)
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Frame capture helper
# ---------------------------------------------------------------------------

def _fig_to_rgb(fig) -> np.ndarray:
    """Return the figure canvas as an H x W x 3 uint8 numpy array."""
    fig.canvas.draw()
    buf = np.frombuffer(fig.canvas.buffer_rgba(), dtype=np.uint8)
    w, h = fig.canvas.get_width_height(physical=True)
    return buf.reshape(h, w, 4)[:, :, :3]


# ---------------------------------------------------------------------------
# Main function
# ---------------------------------------------------------------------------

def make_snow_movie(
    data_struct: dict,
    var_name: str,
    movie_file: str,
    *,
    clim: Sequence[float] | None = None,
    cmap=None,
    fps: int = 10,
    quality: int = 8,
    shapefile: str = "",
    date_range: tuple | None = None,
    title_prefix: str = "",
    skip_days: int = 1,
    latlim: tuple | None = None,
    lonlim: tuple | None = None,
    fig_size: tuple = (12.8, 7.2),
    snotel: bool = True,
) -> None:
    """
    Render an MP4 movie of a snow variable.

    Parameters
    ----------
    data_struct : dict
        Dictionary with keys 'lat', 'lon', 'dates', 'WY', and 3-D arrays
        (nlat x nlon x ndays) for each variable.
    var_name : str
        Key in data_struct to animate.
    movie_file : str
        Output .mp4 filepath.
    clim : (cmin, cmax) or None
        Colour limits.  Auto from 98th-percentile when None.
    cmap : colormap or str or None
        Matplotlib colormap.
    fps : int
        Frames per second.
    quality : int
        imageio quality 0-10 (maps to libx264 crf; 8 ≈ high quality).
    shapefile : str
        Path to shapefile (.shp) overlay.
    date_range : (start_date, end_date) or None
        Subset the animation.  Both elements are date-like.
    title_prefix : str
        Prefix for the frame title.  Auto-detected when empty.
    skip_days : int
        Render every Nth day (1 = every day).
    latlim : (latmin, latmax) or None
    lonlim : (lonmin, lonmax) or None
    fig_size : (width_in, height_in)
        Figure size in inches.
    snotel : bool
        Overlay SNOTEL sites.
    """

    # ---- validate variable -----------------------------------------------
    if var_name not in data_struct:
        three_d = [k for k, v in data_struct.items()
                   if isinstance(v, np.ndarray) and v.ndim == 3]
        raise KeyError(
            f"Variable '{var_name}' not found.\n"
            f"Available 3-D variables:\n  " + "\n  ".join(three_d)
        )

    # ---- coordinates -------------------------------------------------------
    lat = np.asarray(data_struct["lat"], dtype=float)
    lon = np.asarray(data_struct["lon"], dtype=float)

    flip_data = lat[0] > lat[-1]
    if flip_data:
        lat = lat[::-1]

    lat_min, lat_max = lat.min(), lat.max()
    lon_min, lon_max = lon.min(), lon.max()

    latlim = latlim or (lat_min - 0.05, lat_max + 0.05)
    lonlim = lonlim or (lon_min - 0.05, lon_max + 0.05)

    # ---- date indices ------------------------------------------------------
    dates = _dates_as_date(data_struct["dates"])
    n_total = len(dates)

    if date_range is not None:
        d_start = _to_date(date_range[0])
        d_end = _to_date(date_range[1])
        day_idx = [i for i, d in enumerate(dates) if d_start <= d <= d_end]
    else:
        day_idx = list(range(n_total))

    day_idx = day_idx[::skip_days]
    n_frames = len(day_idx)
    print(f"Creating movie: {n_frames} frames, {var_name}, {fps} fps")

    # ---- colour limits from full dataset ----------------------------------
    def_cmap, def_clim, def_units = get_var_defaults(var_name)
    if cmap is None:
        cmap = def_cmap
    if clim is None:
        all_data = data_struct[var_name]
        valid = all_data[(all_data > 0) & np.isfinite(all_data)]
        if valid.size > 0:
            clim = [0.0, float(np.percentile(valid, 98))]
        else:
            clim = [0.0, 1.0]

    # ---- title prefix auto-detect -----------------------------------------
    if not title_prefix:
        if any(k in data_struct for k in ("SWE_mean", "fSCA_mean", "SD_mean")):
            title_prefix = "UCLA SWE"
        else:
            title_prefix = "SNODAS"

    # ---- load static overlays once ----------------------------------------
    shp_gdf = None
    if shapefile:
        shp_path = pathlib.Path(shapefile)
        if shp_path.exists() and HAS_GPD:
            shp_gdf = gpd.read_file(shp_path)
            if shp_gdf.crs and shp_gdf.crs.to_epsg() != 4326:
                shp_gdf = shp_gdf.to_crs(epsg=4326)
        elif not HAS_GPD:
            warnings.warn("geopandas not available; shapefile overlay skipped.")

    snotel_data = None
    if snotel:
        snotel_data = _load_snotel(latlim, lonlim)

    # ---- set up figure and writer -----------------------------------------
    dpi = 100
    fig_w_px = int(fig_size[0] * dpi)
    fig_h_px = int(fig_size[1] * dpi)

    fig = plt.figure(
        figsize=fig_size,
        facecolor="white",
    )

    movie_path = pathlib.Path(movie_file)
    movie_path.parent.mkdir(parents=True, exist_ok=True)

    writer_kwargs = dict(fps=fps, quality=quality, codec="libx264",
                         macro_block_size=None)

    t0 = time.time()
    with imageio.get_writer(str(movie_path), **writer_kwargs) as writer:
        for fi, d in enumerate(day_idx):
            # ---- extract and prep data -----------------------------------
            S = data_struct[var_name][:, :, d].astype(float)
            if flip_data:
                S = np.flipud(S)
            S_masked = np.ma.masked_where((S == 0) | ~np.isfinite(S), S)

            # ---- clear and rebuild axes ----------------------------------
            fig.clf()
            ax = fig.add_subplot(111)
            ax.set_facecolor("white")

            im = ax.imshow(
                S_masked,
                extent=[lon_min, lon_max, lat_min, lat_max],
                origin="lower",
                aspect="equal",
                cmap=cmap,
                vmin=clim[0],
                vmax=clim[1],
                interpolation="nearest",
            )

            ax.set_xlim(lonlim)
            ax.set_ylim(latlim)
            ax.set_xlabel("Longitude", fontsize=11, fontweight="bold")
            ax.set_ylabel("Latitude", fontsize=11, fontweight="bold")
            ax.tick_params(labelsize=10)
            ax.set_aspect("equal")

            # colorbar
            cb = fig.colorbar(im, ax=ax, location="bottom",
                              pad=0.08, fraction=0.04)
            cb.set_label(def_units, fontsize=12, fontweight="bold")
            cb.ax.tick_params(labelsize=10)

            # shapefile overlay
            if shp_gdf is not None:
                shp_gdf.boundary.plot(
                    ax=ax, color=(0.3, 0.3, 0.3), linewidth=2.5, zorder=3
                )

            # SNOTEL overlay
            if snotel_data and snotel_data.get("n_stations", 0) > 0:
                ax.plot(
                    snotel_data["lon"], snotel_data["lat"],
                    "r*", markersize=10, markeredgecolor="darkred",
                    zorder=5,
                )

            # title
            date_str = dates[d].strftime("%Y-%m-%d")
            ax.set_title(
                f"{title_prefix}  {var_name}  {date_str}",
                fontsize=15, fontweight="bold",
            )

            fig.tight_layout()

            # capture frame
            frame_rgb = _fig_to_rgb(fig)
            # ensure even dimensions (required by libx264)
            h, w = frame_rgb.shape[:2]
            if h % 2 != 0:
                frame_rgb = frame_rgb[:-1, :, :]
            if w % 2 != 0:
                frame_rgb = frame_rgb[:, :-1, :]
            writer.append_data(frame_rgb)

            if (fi + 1) % 50 == 0 or fi == 0:
                print(f"  {fi + 1}/{n_frames}", end="\r", flush=True)

    elapsed = time.time() - t0
    print(f"\nMovie saved: {movie_path}  ({n_frames} frames, {elapsed:.1f}s render)")
    plt.close(fig)


# ---------------------------------------------------------------------------
# CLI convenience
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse, pickle

    parser = argparse.ArgumentParser(description="Create a snow-variable movie.")
    parser.add_argument("data_file", help="Pickled data dict (.pkl)")
    parser.add_argument("var_name", help="Variable name")
    parser.add_argument("movie_file", help="Output .mp4 path")
    parser.add_argument("--fps", type=int, default=10)
    parser.add_argument("--skip-days", type=int, default=1)
    parser.add_argument("--shapefile", default="")
    parser.add_argument("--no-snotel", action="store_true")
    args = parser.parse_args()

    with open(args.data_file, "rb") as fh:
        data = pickle.load(fh)

    make_snow_movie(
        data, args.var_name, args.movie_file,
        fps=args.fps,
        skip_days=args.skip_days,
        shapefile=args.shapefile,
        snotel=not args.no_snotel,
    )
