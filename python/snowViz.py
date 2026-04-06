"""
snowViz.py  –  Interactive Snow Data Visualization Driver
=========================================================

Main script for visualising SNODAS and UCLA SWE snow products.
Provides a menu-driven interface to:
  1. Select data source (SNODAS or UCLA SWE)
  2. Choose variable to visualise
  3. Plot a single date  OR  generate a water-year movie (MP4)

PREREQUISITES:
  - Downloaded data pickled as dicts (SNODAS_WY####.pkl, UCLA_SWE_WY####.pkl)
    OR numpy .npz files produced by the Python getSNODAS_WY / getUCLA_SWE scripts.
  - plotSnowVar.py and makeSnowMovie.py in the same directory.

USAGE:
    python snowViz.py

HP Marshall, Boise State University – SnowFusion Project
See also: plotSnowVar.py, makeSnowMovie.py
"""

from __future__ import annotations

import datetime
import glob
import os
import pathlib
import pickle
import sys

import matplotlib
matplotlib.use("TkAgg")          # interactive backend; change to "Qt5Agg" if needed
import matplotlib.pyplot as plt

# ---------------------------------------------------------------------------
# Locate sibling modules
# ---------------------------------------------------------------------------
_HERE = pathlib.Path(__file__).parent.resolve()
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from plotSnowVar import plot_snow_var
from makeSnowMovie import make_snow_movie

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULT_BB = (-116.2, -114.6, 43.2, 44.4)   # (lonmin, lonmax, latmin, latmax)
SCRIPT_DIR = _HERE
DEFAULT_SHAPEFILE = SCRIPT_DIR.parent / "BRB_outline.shp"
DATA_ROOT = pathlib.Path("/Users/hpmarshall/DATA_DRIVE/SnowFusion")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _banner(msg: str) -> None:
    print(f"\n{'=' * 42}")
    print(f"   {msg}")
    print(f"{'=' * 42}\n")


def _choose(prompt: str, choices: list, default=None):
    """Print numbered choices and return the selected item."""
    for i, c in enumerate(choices, 1):
        print(f"  [{i}]  {c}")
    raw = input(f"\n{prompt} ").strip()
    if raw == "" and default is not None:
        return default
    try:
        idx = int(raw) - 1
        if 0 <= idx < len(choices):
            return choices[idx]
    except ValueError:
        pass
    print("Invalid selection.")
    return None


def _load_pkl(path: pathlib.Path) -> dict:
    with open(path, "rb") as fh:
        return pickle.load(fh)


def _find_data_files(directory: pathlib.Path, pattern: str) -> list[pathlib.Path]:
    """Return sorted list of files matching glob pattern inside directory."""
    return sorted(directory.glob(pattern))


# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------

def _load_snodas(data_root: pathlib.Path) -> dict | None:
    snodas_dir = data_root / "SNODAS"
    patterns = ["SNODAS_WY*.pkl", "SNODAS_BRB_WY*.pkl",
                "SNODAS_WY*.npz", "SNODAS_BRB_WY*.npz"]
    files: list[pathlib.Path] = []
    for p in patterns:
        files.extend(_find_data_files(snodas_dir, p))
    files = sorted(set(files))

    if files:
        print("\nFound existing SNODAS files:")
        for i, f in enumerate(files, 1):
            print(f"  [{i}]  {f.name}")
        print("  [0]  (manual path)")
        raw = input("\nSelect file [number]: ").strip()
        if raw == "0":
            path = pathlib.Path(input("Enter full path: ").strip())
        else:
            idx = int(raw) - 1
            path = files[idx]
    else:
        print("\nNo existing SNODAS files found.")
        path = pathlib.Path(input("Enter full path to SNODAS .pkl/.npz file: ").strip())

    print(f"Loading {path} …")
    if path.suffix == ".pkl":
        data = _load_pkl(path)
        # unwrap if saved as {'Snodas': {...}}
        if "Snodas" in data and isinstance(data["Snodas"], dict):
            data = data["Snodas"]
    elif path.suffix == ".npz":
        import numpy as np
        raw = np.load(path, allow_pickle=True)
        data = {k: raw[k] for k in raw.files}
    else:
        raise ValueError(f"Unsupported file format: {path.suffix}")
    return data


def _load_ucla(data_root: pathlib.Path) -> dict | None:
    import datetime
    import numpy as np
    from mosaicUCLA_SR import mosaicUCLA_SR

    wy_raw = input("Water year [default 2021]: ").strip()
    wy = int(wy_raw) if wy_raw else 2021
    wy_str = f"WY{wy - 1}_{str(wy)[2:]}"   # e.g. WY2020_21

    ucla_dir = data_root / "UCLA_SR"
    lat_tiles = [43, 44]
    lon_tiles  = [115, 116, 117]

    print(f"Loading UCLA SR tiles ({wy_str}) from {ucla_dir} …")
    lat, lon, SWE, fSCA, SD = mosaicUCLA_SR(ucla_dir, wy_str, lat_tiles, lon_tiles)

    # Ensure lat ascending (south to north) for correct imshow orientation
    if lat[0] > lat[-1]:
        lat  = lat[::-1]
        SWE  = SWE[::-1,  ...]
        fSCA = fSCA[::-1, ...]
        SD   = SD[::-1,   ...]

    n_days   = SWE.shape[3]
    wy_start = datetime.date(wy - 1, 10, 1)
    dates    = [wy_start + datetime.timedelta(days=i) for i in range(n_days)]

    data = {
        "lat":        lat,
        "lon":        lon,
        "dates":      dates,
        "WY":         wy,
        # ensemble axis 2: 0=mean, 1=std, 2=p25, 3=median, 4=p75
        "SWE_mean":   SWE[:, :, 0, :].astype(float),
        "SWE_std":    SWE[:, :, 1, :].astype(float),
        "SWE_p25":    SWE[:, :, 2, :].astype(float),
        "SWE_median": SWE[:, :, 3, :].astype(float),
        "SWE_p75":    SWE[:, :, 4, :].astype(float),
        "fSCA_mean":  fSCA[:, :, 0, :].astype(float),
        "SD_mean":    SD[:, :, 0, :].astype(float),
        "SD_std":     SD[:, :, 1, :].astype(float),
        "SD_median":  SD[:, :, 3, :].astype(float),
    }
    print(f"  UCLA grid: {len(lat)} lat x {len(lon)} lon, {n_days} days")
    return data


# ---------------------------------------------------------------------------
# Main interactive flow
# ---------------------------------------------------------------------------

def main() -> None:
    _banner("SnowFusion Visualization Tool")

    # ------------------------------------------------------------------
    # STEP 1: Select data source
    # ------------------------------------------------------------------
    print("Data Sources:")
    print("  [1]  SNODAS (NOAA Snow Data Assimilation System)")
    print("         Variables: SWE, Depth, Precip, SnowPrecip, Tsnow, Melt,")
    print("                    Sublimation, SublimationBS\n")
    print("  [2]  UCLA SWE (Western US Snow Reanalysis)")
    print("         Variables: SWE_mean, SWE_median, SWE_std, SWE_p25, SWE_p75,")
    print("                    fSCA_mean, SD_mean, SD_median, SD_std\n")

    source_raw = input("Select data source [1 or 2]: ").strip()

    if source_raw == "1":
        src_name = "SNODAS"
        all_vars = ["SWE", "Depth", "Precip", "SnowPrecip", "Tsnow",
                    "Melt", "Sublimation", "SublimationBS"]
        data = _load_snodas(DATA_ROOT)

    elif source_raw == "2":
        src_name = "UCLA SWE"
        all_vars = ["SWE_mean", "SWE_median", "SWE_std", "SWE_p25", "SWE_p75",
                    "fSCA_mean", "SD_mean", "SD_median", "SD_std"]
        data = _load_ucla(DATA_ROOT)

    else:
        print("Invalid selection. Please choose 1 or 2.")
        return

    if data is None:
        print("No data loaded – exiting.")
        return

    # ------------------------------------------------------------------
    # STEP 2: Select variable
    # ------------------------------------------------------------------
    print(f"\n--- Available Variables for {src_name} ---")
    avail_vars = [v for v in all_vars if v in data]
    if not avail_vars:
        # fall back: any 3-D array key
        import numpy as np
        avail_vars = [k for k, v in data.items()
                      if isinstance(v, np.ndarray) and v.ndim == 3]
    if not avail_vars:
        print("No plottable variables found in the loaded data.")
        return

    for i, v in enumerate(avail_vars, 1):
        print(f"  [{i}]  {v}")
    var_raw = input("\nSelect variable [number]: ").strip()
    selected_var = avail_vars[int(var_raw) - 1]
    print(f"Selected: {selected_var}")

    # ------------------------------------------------------------------
    # STEP 3: Choose mode
    # ------------------------------------------------------------------
    print("\n--- Visualization Mode ---")
    print("  [1]  Single date figure")
    print("  [2]  Water year movie (MP4)")
    print("  [3]  Both")
    mode_raw = input("\nSelect mode [1, 2, or 3]: ").strip()

    # shapefile option
    shp_arg = str(DEFAULT_SHAPEFILE) if DEFAULT_SHAPEFILE.exists() else ""

    # ------------------------------------------------------------------
    # STEP 4a: Single date figure
    # ------------------------------------------------------------------
    if mode_raw in ("1", "3"):
        dates = data.get("dates", [])
        if dates:
            import numpy as np
            from plotSnowVar import _dates_as_date
            dlist = _dates_as_date(dates)
            print(f"\nDate range: {dlist[0]} to {dlist[-1]}")
        date_input = input("Enter date (YYYY-MM-DD): ").strip()

        print("Generating figure …")
        fig, ax, im = plot_snow_var(
            data, selected_var, date_input,
            shapefile=shp_arg,
        )
        plt.show(block=False)

        save_choice = input("Save figure? [y/n]: ").strip().lower()
        if save_choice == "y":
            out_name = f"{src_name}_{selected_var}_{date_input}.png".replace(" ", "_")
            fig.savefig(out_name, dpi=200, bbox_inches="tight")
            print(f"Saved: {out_name}")

    # ------------------------------------------------------------------
    # STEP 4b: Water year movie
    # ------------------------------------------------------------------
    if mode_raw in ("2", "3"):
        fps_raw = input("Frames per second (default 10): ").strip()
        fps = int(fps_raw) if fps_raw else 10

        skip_raw = input("Skip days (1=every day, 2=every other; default 1): ").strip()
        skip_days = int(skip_raw) if skip_raw else 1

        movies_dir = DATA_ROOT / "Movies"
        movies_dir.mkdir(parents=True, exist_ok=True)

        wy = data.get("WY", "unknown")
        safe_src = src_name.replace(" ", "_")
        movie_file = movies_dir / f"{safe_src}_{selected_var}_WY{wy}.mp4"
        print(f"Output: {movie_file}")

        print("Generating movie …")
        make_snow_movie(
            data, selected_var, str(movie_file),
            fps=fps,
            skip_days=skip_days,
            shapefile=shp_arg,
        )
        print(f"\nMovie complete: {movie_file}")

    _banner("Done! SnowFusion Visualization")


if __name__ == "__main__":
    main()
