"""
getUCLA_SWE.py
Load UCLA SWE Snow Reanalysis tiles for a region and water year.

Translated from getUCLA_SWE.m (HP Marshall, Boise State University).

Dataset:   https://nsidc.org/data/wus_ucla_sr/versions/1
Resolution: ~500 m (16 arc-seconds), 225 pixels per degree
Coverage:  WY1985 – WY2021

Usage
-----
    from getUCLA_SWE import get_ucla_swe

    ucla = get_ucla_swe(
        wy=2020,
        bb=[-116.2, -114.6, 43.2, 44.4],   # [lonmin, lonmax, latmin, latmax]
        data_dir="/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR",
    )

Output dictionary keys
----------------------
    wy          - int, water year
    lat         - 1-D ndarray, latitudes  (south → north)
    lon         - 1-D ndarray, longitudes (west  → east, negative values)
    dates       - list of datetime.date objects (Oct 1 → Sep 30)
    date_strs   - list of 'YYYY-MM-DD' strings
    SWE_mean    - ndarray [ny × nx × ndays], posterior SWE mean [m]
    SWE_std     - ndarray [ny × nx × ndays], posterior SWE std  [m]
    SWE_median  - ndarray [ny × nx × ndays], posterior SWE median [m]
    SWE_p25     - ndarray [ny × nx × ndays], 25th-percentile SWE [m]
    SWE_p75     - ndarray [ny × nx × ndays], 75th-percentile SWE [m]
    fSCA_mean   - ndarray [ny × nx × ndays], fractional snow cover mean [-]
    SD_mean     - ndarray [ny × nx × ndays], snow depth mean   [m]
    SD_std      - ndarray [ny × nx × ndays], snow depth std    [m]
    SD_median   - ndarray [ny × nx × ndays], snow depth median [m]
    SD_p25      - ndarray [ny × nx × ndays], 25th-percentile SD [m]
    SD_p75      - ndarray [ny × nx × ndays], 75th-percentile SD [m]

Ensemble-stat index mapping (0-based in Python, matching file dimension 2)
    0 = mean, 1 = std, 2 = median, 3 = 25th pctl, 4 = 75th pctl

HP Marshall, Boise State University — SnowFusion Project
"""

from __future__ import annotations

import pathlib
import calendar
from datetime import date, timedelta

import numpy as np
import netCDF4  # type: ignore

# ---------------------------------------------------------------------------
# Default bounding box (Boise River Basin)
# ---------------------------------------------------------------------------
DEFAULT_BB      = [-116.2, -114.6, 43.2, 44.4]  # [lonmin, lonmax, latmin, latmax]
DEFAULT_DATA_DIR = pathlib.Path(
    "/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR"
)

# Ensemble-stat index ordering inside the NetCDF files (0-based)
STAT_NAMES   = ["mean", "std", "median", "p25", "p75"]
N_STATS      = len(STAT_NAMES)

# Minimum byte size to accept a file as valid
MIN_VALID_BYTES = 1_000_000


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def get_ucla_swe(
    wy: int,
    bb: list[float] | None = None,
    data_dir: str | pathlib.Path | None = None,
) -> dict:
    """Load UCLA SWE Snow Reanalysis tiles and return a data dictionary.

    Parameters
    ----------
    wy : int
        Water year (e.g. 2020 covers Oct 2019 – Sep 2020).
        Valid range: 1985 – 2021.
    bb : list of float, optional
        Bounding box [lonmin, lonmax, latmin, latmax].
        Defaults to Boise River Basin: [-116.2, -114.6, 43.2, 44.4].
    data_dir : str or Path, optional
        Directory containing downloaded UCLA .nc files.
        Defaults to /Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR.

    Returns
    -------
    dict
        See module docstring for full key descriptions.
    """
    if bb is None:
        bb = DEFAULT_BB
    if data_dir is None:
        data_dir = DEFAULT_DATA_DIR
    data_dir = pathlib.Path(data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)

    lon_min, lon_max, lat_min, lat_max = bb

    # ---- Determine tiles needed ----
    # Tiles are named by their lower-left (SW) corner.
    # West longitudes are stored as positive integers in filenames.
    lat_tiles = list(range(int(np.floor(lat_min)), int(np.floor(lat_max)) + 1))
    # abs(lon_max) < abs(lon_min) because lon_max is less negative
    lon_tiles = list(range(int(np.floor(abs(lon_max))),
                           int(np.floor(abs(lon_min))) + 1))

    print(f"UCLA SWE: need {len(lat_tiles)} × {len(lon_tiles)} tiles for bounding box")
    tile_names_str = "  ".join(
        f"N{lt}_0_W{ln}_0" for lt in lat_tiles for ln in lon_tiles
    )
    print(f"  Tiles: {tile_names_str}")

    # ---- Water-year date vector ----
    dates, n_days_wy = _make_wy_dates(wy)

    # ---- Load tiles ----
    tile_data = _load_swe_sca_tiles(lat_tiles, lon_tiles, data_dir)
    _load_sd_tiles(lat_tiles, lon_tiles, data_dir, tile_data)

    if not tile_data:
        raise FileNotFoundError(
            f"No UCLA SWE tiles found in {data_dir}. "
            "Download data first (run getUCLA_SR_BRB.py)."
        )

    # ---- Assemble mosaic ----
    all_lat, all_lon = _collect_coordinates(tile_data)

    # Subset to bounding box
    lat_mask = (all_lat >= lat_min) & (all_lat <= lat_max)
    lon_mask = (all_lon >= lon_min) & (all_lon <= lon_max)
    out_lat  = all_lat[lat_mask]
    out_lon  = all_lon[lon_mask]
    ny, nx   = len(out_lat), len(out_lon)

    print(f"Output grid: {ny} × {nx} pixels  (lat × lon)")
    print(f"Days in WY{wy}: {n_days_wy}")

    # ---- Initialise output arrays (NaN) ----
    ucla: dict = {
        "wy":        wy,
        "lat":       out_lat,
        "lon":       out_lon,
        "dates":     dates,
        "date_strs": [d.strftime("%Y-%m-%d") for d in dates],
    }
    for stat in STAT_NAMES:
        ucla[f"SWE_{stat}"]  = np.full((ny, nx, n_days_wy), np.nan, dtype=np.float32)
        ucla[f"SD_{stat}"]   = np.full((ny, nx, n_days_wy), np.nan, dtype=np.float32)
    ucla["fSCA_mean"] = np.full((ny, nx, n_days_wy), np.nan, dtype=np.float32)

    # ---- Map each tile into the output mosaic ----
    _fill_mosaic(tile_data, ucla, out_lat, out_lon, n_days_wy)

    # ---- Save to npz ----
    out_file = data_dir / f"UCLA_SWE_WY{wy}.npz"
    print(f"Saving to {out_file}...")
    _save_npz(ucla, out_file)
    print(f"Done! UCLA SWE WY{wy} loaded and saved.")

    return ucla


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _make_wy_dates(wy: int) -> tuple[list[date], int]:
    """Return (list_of_dates, n_days) for the water year starting Oct 1 of wy-1."""
    start = date(wy - 1, 10, 1)
    # Leap year is based on the calendar year that contains Feb
    n_days = 366 if calendar.isleap(wy) else 365
    dates  = [start + timedelta(days=i) for i in range(n_days)]
    return dates, n_days


def _swe_sca_filename(lat: int, lon_w: int) -> str:
    return f"N{lat}_0_W{lon_w}_0_SWE_SCA_POST_v001.nc"


def _sd_filename(lat: int, lon_w: int) -> str:
    return f"N{lat}_0_W{lon_w}_0_SD_POST_v001.nc"


def _tile_key(lat: int, lon_w: int) -> str:
    return f"N{lat}_W{lon_w}"


def _inspect_variable_names(ds: netCDF4.Dataset) -> None:
    """Print dimension and variable info for debugging."""
    dims_str = "  ".join(
        f"{n}={d.size}" for n, d in ds.dimensions.items()
    )
    print(f"  dims: {dims_str}")
    print(f"  vars: {list(ds.variables.keys())}")


def _find_var(ds: netCDF4.Dataset, keywords: list[str], exclude: list[str]) -> str | None:
    """Return the first variable name matching any keyword but not any exclusion."""
    coord_names = {"lat", "lon", "latitude", "longitude", "time", "stats"}
    for vname in ds.variables:
        vl = vname.lower()
        if vl in coord_names:
            continue
        if any(ex.lower() in vl for ex in exclude):
            continue
        if any(kw.lower() in vl for kw in keywords):
            return vname
    # Fall back: first non-coordinate variable
    for vname in ds.variables:
        if vname.lower() not in coord_names:
            return vname
    return None


def _read_coords(ds: netCDF4.Dataset) -> tuple[np.ndarray, np.ndarray]:
    """Return (lat, lon) 1-D arrays from a tile NetCDF dataset."""
    for lat_name in ("lat", "latitude", "Latitude"):
        if lat_name in ds.variables:
            lat = ds.variables[lat_name][:]
            break
    else:
        raise KeyError("Cannot find latitude variable in NetCDF file.")

    for lon_name in ("lon", "longitude", "Longitude"):
        if lon_name in ds.variables:
            lon = ds.variables[lon_name][:]
            break
    else:
        raise KeyError("Cannot find longitude variable in NetCDF file.")

    return np.asarray(lat), np.asarray(lon)


def _load_swe_sca_tiles(
    lat_tiles: list[int],
    lon_tiles: list[int],
    data_dir: pathlib.Path,
) -> dict:
    """Read SWE/fSCA tiles into a dict keyed by tile ID."""
    tile_data: dict = {}
    print(f"Loading SWE/fSCA tiles...")

    for lt in lat_tiles:
        for ln in lon_tiles:
            fname = _swe_sca_filename(lt, ln)
            fpath = data_dir / fname

            if not fpath.exists() or fpath.stat().st_size < MIN_VALID_BYTES:
                print(f"  WARNING: {fname} not found or too small. Skipping tile.")
                continue

            key = _tile_key(lt, ln)
            print(f"  Reading {fname}")

            with netCDF4.Dataset(fpath) as ds:
                _inspect_variable_names(ds)
                lat, lon = _read_coords(ds)

                swe_name  = _find_var(ds, ["SWE", "swe"], [])
                fsca_name = _find_var(ds, ["SCA", "fSCA", "sca", "fsca"], [])

                if swe_name is None:
                    print(f"  WARNING: no SWE variable found in {fname}")
                    continue
                print(f"  Reading SWE variable: {swe_name}")

                # Load as float32; mask → NaN
                swe_data = np.ma.filled(
                    ds.variables[swe_name][:].astype(np.float32), np.nan
                )

                tile_data[key] = {"lat": lat, "lon": lon, "swe": swe_data}

                if fsca_name and fsca_name != swe_name:
                    print(f"  Reading fSCA variable: {fsca_name}")
                    fsca_data = np.ma.filled(
                        ds.variables[fsca_name][:].astype(np.float32), np.nan
                    )
                    tile_data[key]["fsca"] = fsca_data

    return tile_data


def _load_sd_tiles(
    lat_tiles: list[int],
    lon_tiles: list[int],
    data_dir: pathlib.Path,
    tile_data: dict,
) -> None:
    """Augment tile_data dict in-place with snow depth arrays."""
    print("Loading Snow Depth tiles...")

    for lt in lat_tiles:
        for ln in lon_tiles:
            fname = _sd_filename(lt, ln)
            fpath = data_dir / fname
            key   = _tile_key(lt, ln)

            if not fpath.exists() or fpath.stat().st_size < MIN_VALID_BYTES:
                print(f"  WARNING: {fname} not found or too small.")
                continue

            print(f"  Reading {fname}")

            with netCDF4.Dataset(fpath) as ds:
                sd_name = _find_var(ds, ["SD", "sd", "depth", "snow_depth"], [])

                if sd_name is None:
                    print(f"  WARNING: no SD variable found in {fname}")
                    continue

                print(f"  Reading SD variable: {sd_name}")
                sd_data = np.ma.filled(
                    ds.variables[sd_name][:].astype(np.float32), np.nan
                )

                if key not in tile_data:
                    # Tile has SD but no SWE file — create partial entry
                    with netCDF4.Dataset(fpath) as ds2:
                        lat, lon = _read_coords(ds2)
                    tile_data[key] = {"lat": lat, "lon": lon}

                tile_data[key]["sd"] = sd_data


def _collect_coordinates(tile_data: dict) -> tuple[np.ndarray, np.ndarray]:
    """Return sorted unique lat and lon arrays across all loaded tiles."""
    all_lat: list[np.ndarray] = []
    all_lon: list[np.ndarray] = []
    for td in tile_data.values():
        all_lat.append(td["lat"].ravel())
        all_lon.append(td["lon"].ravel())
    lat = np.unique(np.concatenate(all_lat))
    lon = np.unique(np.concatenate(all_lon))
    return lat, lon


def _find_index_map(values: np.ndarray, target: np.ndarray) -> np.ndarray:
    """Return integer indices so that values[idx] == target (matched subset)."""
    # Build a lookup from value → position in values
    sorter = np.argsort(values)
    idx = np.searchsorted(values, target, sorter=sorter)
    idx = sorter[np.clip(idx, 0, len(sorter) - 1)]
    valid = values[idx] == target
    return idx[valid]


def _fill_mosaic(
    tile_data: dict,
    ucla: dict,
    out_lat: np.ndarray,
    out_lon: np.ndarray,
    n_days: int,
) -> None:
    """Map each tile's arrays into the assembled output mosaic."""
    print("Assembling tile mosaic...")

    for key, td in tile_data.items():
        tile_lat = td["lat"].ravel()
        tile_lon = td["lon"].ravel()

        # Indices of this tile's coords that fall inside the output grid
        lat_in_out = np.isin(tile_lat, out_lat)
        lon_in_out = np.isin(tile_lon, out_lon)

        if not lat_in_out.any() or not lon_in_out.any():
            continue

        # Positions within the output grid
        tile_lat_vals = tile_lat[lat_in_out]
        tile_lon_vals = tile_lon[lon_in_out]
        lat_out_idx = np.searchsorted(out_lat, tile_lat_vals)
        lon_out_idx = np.searchsorted(out_lon, tile_lon_vals)

        nly = len(lat_out_idx)
        nlx = len(lon_out_idx)

        # ---- SWE ----
        if "swe" in td:
            swe = td["swe"]
            swe_shape = swe.shape
            print(f"  Tile {key} SWE shape: {swe_shape}")

            # Expected layout: [lat x lon x stats x days]  (225×225×5×366)
            # Handle both [lat,lon,stats,days] and [lon,lat,stats,days]
            if len(swe_shape) == 4:
                n_s = min(N_STATS, swe_shape[2])
                n_d = min(n_days, swe_shape[3])
                for si in range(n_s):
                    stat = STAT_NAMES[si]
                    slice_2d = swe[:nly, :nlx, si, :n_d]  # [nly, nlx, n_d]
                    out_grid_lat = lat_out_idx[:nly]
                    out_grid_lon = lon_out_idx[:nlx]
                    target = ucla[f"SWE_{stat}"]
                    target[np.ix_(out_grid_lat, out_grid_lon, np.arange(n_d))] = slice_2d

        # ---- fSCA ----
        if "fsca" in td:
            fsca = td["fsca"]
            if fsca.ndim >= 3:
                n_d = min(n_days, fsca.shape[-1])
                slice_2d = fsca[:nly, :nlx, 0, :n_d] if fsca.ndim == 4 else fsca[:nly, :nlx, :n_d]
                out_grid_lat = lat_out_idx[:nly]
                out_grid_lon = lon_out_idx[:nlx]
                ucla["fSCA_mean"][np.ix_(out_grid_lat, out_grid_lon, np.arange(n_d))] = slice_2d

        # ---- SD ----
        if "sd" in td:
            sd = td["sd"]
            sd_shape = sd.shape
            print(f"  Tile {key} SD shape: {sd_shape}")

            if len(sd_shape) == 4:
                n_s = min(N_STATS, sd_shape[2])
                n_d = min(n_days, sd_shape[3])
                for si in range(n_s):
                    stat = STAT_NAMES[si]
                    slice_2d = sd[:nly, :nlx, si, :n_d]
                    out_grid_lat = lat_out_idx[:nly]
                    out_grid_lon = lon_out_idx[:nlx]
                    target = ucla[f"SD_{stat}"]
                    target[np.ix_(out_grid_lat, out_grid_lon, np.arange(n_d))] = slice_2d


def _save_npz(ucla: dict, out_file: pathlib.Path) -> None:
    """Save the UCLA dict to a compressed .npz file.

    Non-array fields (wy, dates, date_strs) are stored as object arrays
    so they survive the round-trip through np.load(..., allow_pickle=True).
    """
    save_dict: dict[str, np.ndarray] = {}
    for k, v in ucla.items():
        if isinstance(v, np.ndarray):
            save_dict[k] = v
        elif isinstance(v, (int, float)):
            save_dict[k] = np.array(v)
        else:
            # dates, date_strs — store as object array
            save_dict[k] = np.array(v, dtype=object)
    np.savez_compressed(out_file, **save_dict)


# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------

def _parse_args():
    import argparse

    parser = argparse.ArgumentParser(
        description="Load UCLA SWE Snow Reanalysis tiles for a water year."
    )
    parser.add_argument(
        "wy", type=int,
        help="Water year (e.g. 2020 = Oct 2019 – Sep 2020). Range: 1985-2021.",
    )
    parser.add_argument(
        "--bb", type=float, nargs=4,
        metavar=("LONMIN", "LONMAX", "LATMIN", "LATMAX"),
        default=None,
        help=(
            "Bounding box in degrees. "
            "Default: Boise River Basin [-116.2 -114.6 43.2 44.4]."
        ),
    )
    parser.add_argument(
        "--data-dir", type=str, default=None,
        help="Directory containing downloaded UCLA .nc files.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    get_ucla_swe(
        wy=args.wy,
        bb=args.bb,
        data_dir=args.data_dir,
    )
