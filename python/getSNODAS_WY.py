"""
getSNODAS_WY.py
Download SNODAS data for a water year and bounding box via HTTPS.

This is the function-based companion to getSNODAS_BRB.py.
The original MATLAB version used anonymous FTP; this version uses the
NSIDC HTTPS endpoint (no authentication required).

Dataset: https://nsidc.org/data/g02158/versions/1
Resolution: ~1 km (30 arc-sec), daily, 2003-present

HP Marshall, Boise State University
SnowFusion Project
"""

import gzip
import shutil
import tarfile
from datetime import date, timedelta
from pathlib import Path
from typing import Optional

import numpy as np
import requests

# ====== SNODAS GRID CONSTANTS ======
_LON_MIN = -124.733749999999
_LON_MAX = -66.9420833333342
_LAT_MIN =  24.9495833333335
_LAT_MAX =  52.8745833333323
_N_COLS  = 6935
_N_ROWS  = 3351

_PROD_CODES = ['1025SlL00', '1025SlL01', '1034', '1036', '1038', '1039', '1044', '1050']
_PROD_NAMES = ['Precip', 'SnowPrecip', 'SWE', 'Depth', 'Tsnow', 'SublimationBS', 'Melt', 'Sublimation']

# Scale factors: multiply raw int16 to reach standard physical units
# Precip/SnowPrecip: raw = value * 10  (mm)      -> / 10
# SWE/Depth:         raw = value * 1000 (m)       -> / 1000
# Tsnow:             raw = K (no scaling)          -> * 1
# SublimationBS/Melt/Sublimation: raw = value*1e5 -> / 1e5
_SCALE = [1/10, 1/10, 1/1000, 1/1000, 1.0, 1/1e5, 1/1e5, 1/1e5]

_BASE_URL    = 'https://noaadata.apps.nsidc.org/NOAA/G02158/masked/'
_MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

_DEFAULT_OUT_DIR = Path('/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS')
_DEFAULT_BB      = [-116.2, -114.6, 43.2, 44.4]  # Boise River Basin [lonmin lonmax latmin latmax]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _build_date_list(wy: int) -> list[date]:
    """Return list of dates for water year wy (Oct 1, wy-1 through Sep 30, wy)."""
    start = date(wy - 1, 10, 1)
    end   = date(wy, 9, 30)
    n = (end - start).days + 1
    return [start + timedelta(days=i) for i in range(n)]


def _download_tar(url: str, dest: Path, timeout: int = 120) -> bool:
    """Stream-download url to dest. Returns True on success."""
    try:
        with requests.get(url, stream=True, timeout=timeout) as r:
            r.raise_for_status()
            with open(dest, 'wb') as f:
                for chunk in r.iter_content(chunk_size=1 << 16):
                    f.write(chunk)
        return True
    except requests.RequestException as e:
        print(f'  download error: {e}')
        return False


def _extract_tar(tar_path: Path, dest_dir: Path) -> bool:
    """Extract tar archive to dest_dir, then delete it. Returns True on success."""
    try:
        with tarfile.open(tar_path) as tf:
            tf.extractall(dest_dir)
        tar_path.unlink()
        return True
    except Exception as e:
        print(f'  untar error: {e}')
        return False


def _gunzip(gz_path: Path) -> Path:
    """Decompress gz_path in-place, delete .gz, return path to decompressed file."""
    out_path = gz_path.with_suffix('')
    with gzip.open(gz_path, 'rb') as f_in, open(out_path, 'wb') as f_out:
        shutil.copyfileobj(f_in, f_out)
    gz_path.unlink()
    return out_path


def _read_snodas_binary(dat_path: Path) -> np.ndarray:
    """
    Read a SNODAS flat binary file.
    Returns array shaped [N_ROWS x N_COLS], dtype float32.
    Raw encoding: int16 big-endian, stored row-major (lat north-to-south).
    """
    raw = dat_path.read_bytes()
    D = np.frombuffer(raw, dtype='>i2').reshape(_N_ROWS, _N_COLS)
    return D.astype(np.float32)


def _load_day_cache(npz_path: Path, expected_shape: tuple) -> Optional[dict]:
    """
    Load a cached daily .npz file.
    Returns data dict, or None if missing or grid shape doesn't match expected_shape.
    A shape mismatch means the bounding box changed — file is deleted so it will
    be re-downloaded.
    """
    if not npz_path.exists():
        return None
    data = dict(np.load(npz_path, allow_pickle=True))
    first = next((n for n in _PROD_NAMES if n in data), None)
    if first is None:
        return None
    if data[first].shape != expected_shape:
        print(f'  cache size mismatch (expected {expected_shape}, '
              f'got {data[first].shape}), re-downloading')
        npz_path.unlink()
        return None
    return data


def _clean_dir(directory: Path) -> None:
    """Remove all non-directory files from directory."""
    for p in directory.iterdir():
        if p.is_file():
            p.unlink()


# ---------------------------------------------------------------------------
# Public function
# ---------------------------------------------------------------------------

def get_snodas_wy(
    wy: int,
    bb: Optional[list] = None,
    out_dir: Optional[Path] = None,
) -> dict:
    """
    Download SNODAS data for a water year and bounding box.

    Parameters
    ----------
    wy : int
        Water year (e.g. 2020 = Oct 2019 through Sep 2020).
    bb : list, optional
        Bounding box [lonmin, lonmax, latmin, latmax].
        Default: Boise River Basin [-116.2, -114.6, 43.2, 44.4].
    out_dir : Path or str, optional
        Directory for saving .npz output files.
        Default: /Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS

    Returns
    -------
    snodas : dict
        Keys:
          'WY'           - water year (int)
          'lat'          - latitude vector, north-to-south (1-D ndarray)
          'lon'          - longitude vector, west-to-east (1-D ndarray)
          'dates'        - Python ordinal integers for each day (1-D ndarray)
          'datestr'      - ISO date strings YYYY-MM-DD (1-D object array)
          'SWE'          - Snow Water Equivalent [m]        (ny x nx x ndays float32)
          'Depth'        - Snow Depth [m]                   (ny x nx x ndays float32)
          'Precip'       - Precipitation [mm]               (ny x nx x ndays float32)
          'SnowPrecip'   - Snow Precipitation [mm w.e.]     (ny x nx x ndays float32)
          'Tsnow'        - Snow Temperature [K]             (ny x nx x ndays float32)
          'Melt'         - Snowmelt [m]                     (ny x nx x ndays float32)
          'Sublimation'  - Pack sublimation [m]             (ny x nx x ndays float32)
          'SublimationBS'- Blowing-snow sublimation [m]     (ny x nx x ndays float32)

    Notes
    -----
    - No-data fill value (-9999 in raw int16) is replaced with NaN.
    - Unit conversions are applied during the per-day read (before caching).
    - A per-day .npz cache is written to out_dir. If the bounding box changes
      the old cache files are discarded automatically (size-mismatch check).
    - The full water-year result is saved as SNODAS_WY<wy>.npz in out_dir.
    - Downloads use NSIDC HTTPS (replaces the legacy FTP used in the MATLAB version).
    """

    if bb is None:
        bb = _DEFAULT_BB
    if out_dir is None:
        out_dir = _DEFAULT_OUT_DIR
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    tmp_dir = out_dir / 'SNODAS_tmp'
    tmp_dir.mkdir(parents=True, exist_ok=True)

    # ---- SNODAS grid ----
    lon_full = np.linspace(_LON_MIN, _LON_MAX, _N_COLS)
    lat_full = np.linspace(_LAT_MAX, _LAT_MIN, _N_ROWS)  # north to south

    # ---- Subset indices (strict interior, matching MATLAB > / < logic) ----
    lon_min_bb, lon_max_bb, lat_min_bb, lat_max_bb = bb
    Ix = np.where((lon_full > lon_min_bb) & (lon_full < lon_max_bb))[0]
    Iy = np.where((lat_full > lat_min_bb) & (lat_full < lat_max_bb))[0]
    nx, ny = len(Ix), len(Iy)
    expected_shape = (ny, nx)

    snodas: dict = {
        'WY':  wy,
        'lat': lat_full[Iy],
        'lon': lon_full[Ix],
    }

    # ---- Date list ----
    all_dates = _build_date_list(wy)
    n_days    = len(all_dates)
    date_strs = [d.strftime('%Y-%m-%d') for d in all_dates]
    snodas['dates']   = np.array([d.toordinal() for d in all_dates])
    snodas['datestr'] = np.array(date_strs)

    # ---- Pre-allocate output arrays (NaN-filled) ----
    for name in _PROD_NAMES:
        snodas[name] = np.full((ny, nx, n_days), np.nan, dtype=np.float32)

    # ---- Download loop ----
    print(f'Connecting to SNODAS HTTPS server...')
    print(f'Downloading SNODAS for WY{wy} ({n_days} days)...')

    for d, (dt, ds) in enumerate(zip(all_dates, date_strs)):
        yyyy, mm, dd_day = dt.year, dt.month, dt.day
        month_dir = f'{mm:02d}_{_MONTH_NAMES[mm - 1]}'
        tar_name  = f'SNODAS_{yyyy:04d}{mm:02d}{dd_day:02d}.tar'
        npz_file  = out_dir / f'SNODAS_{yyyy:04d}{mm:02d}{dd_day:02d}.npz'

        # ---- Check per-day cache ----
        cached = _load_day_cache(npz_file, expected_shape)
        if cached is not None:
            for name in _PROD_NAMES:
                if name in cached:
                    snodas[name][:, :, d] = cached[name]
            if (d + 1) % 30 == 0:
                print(f'  [{ds}] {d+1}/{n_days} days complete (cached).')
            continue

        # ---- Build URL and download tar ----
        url      = f'{_BASE_URL}{yyyy:04d}/{month_dir}/{tar_name}'
        tar_path = tmp_dir / tar_name

        if not _download_tar(url, tar_path):
            print(f'  [{ds}] No data found, skipping.')
            continue

        if not _extract_tar(tar_path, tmp_dir):
            print(f'  [{ds}] Extraction failed, skipping.')
            continue

        # ---- Read each variable ----
        day_data: dict = {}
        for code, name, scale in zip(_PROD_CODES, _PROD_NAMES, _SCALE):
            gz_files = sorted(tmp_dir.glob(f'*{code}*.dat.gz'))
            if not gz_files:
                continue

            _gunzip(gz_files[0])

            dat_files = sorted(tmp_dir.glob(f'*{code}*.dat'))
            if not dat_files:
                continue

            D = _read_snodas_binary(dat_files[0])   # float32 [N_ROWS x N_COLS]
            D[D == -9999] = np.nan                   # fill -> NaN before scaling
            D_sub = D[np.ix_(Iy, Ix)] * scale        # subset and scale

            snodas[name][:, :, d] = D_sub
            day_data[name] = D_sub

            dat_files[0].unlink()

        # ---- Clean remaining temp files ----
        _clean_dir(tmp_dir)

        # ---- Save daily cache ----
        day_data['lat']  = lat_full[Iy]
        day_data['lon']  = lon_full[Ix]
        day_data['date'] = np.array([dt.toordinal()])
        np.savez(npz_file, **day_data)

        if (d + 1) % 30 == 0:
            print(f'  [{ds}] {d+1}/{n_days} days complete.')

    # ---- Save full water year ----
    out_file = out_dir / f'SNODAS_WY{wy}.npz'
    print(f'Saving to {out_file}...')
    np.savez(out_file, **snodas)
    print(f'Done! SNODAS WY{wy} downloaded and saved.')

    # ---- Clean up temp directory ----
    try:
        shutil.rmtree(tmp_dir)
    except Exception:
        pass

    return snodas


# ---------------------------------------------------------------------------
# Command-line entry point (mirrors the MATLAB script usage)
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    import sys

    wy     = int(sys.argv[1]) if len(sys.argv) > 1 else 2020
    bb     = None   # use default BRB bbox
    result = get_snodas_wy(wy, bb=bb)

    print('\n=== Summary ===')
    print(f'Water Year : {result["WY"]}')
    print(f'Grid       : {result["lat"].size} rows x {result["lon"].size} cols')
    for name in _PROD_NAMES:
        arr = result[name]
        pct = 100 * np.sum(~np.isnan(arr)) / arr.size
        print(f'  {name}: {pct:.1f}% valid data')
