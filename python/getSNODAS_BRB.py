"""
getSNODAS_BRB.py
Downloads SNODAS (G02158) data for the Boise River Basin from NSIDC
using HTTPS access.

Dataset: https://nsidc.org/data/g02158/versions/1
Resolution: ~1 km (30 arc-sec), daily, 2003-present

Variables (8 total):
  1025SlL00 - Precipitation (liquid, kg/m^2)
  1025SlL01 - Snowfall (solid precip, kg/m^2)
  1034      - Snow Water Equivalent (m * 1000)
  1036      - Snow Depth (m * 1000)
  1038      - Snow pack average temperature (K * 1)
  1039      - Blowing snow sublimation (m * 100000)
  1044      - Snow melt (m * 100000)
  1050      - Snow pack sublimation (m * 100000)

Grid: 6935 x 3351 pixels, flat binary int16, big-endian
Bounding box: lon [-124.7337, -66.9421], lat [24.9496, 52.8746]

Based on getSNODAS_BRB.m by HP Marshall
Updated to Python, April 2026

HP Marshall, Boise State University
"""

import gzip
import shutil
import tarfile
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import requests

# ====== USER CONFIGURATION ======
WY = 2021  # Water year to download (e.g. 2021 = Oct 2020 - Sep 2021)

DATA_ROOT = Path('/Users/hpmarshall/DATA_DRIVE/SnowFusion')
OUT_DIR   = DATA_ROOT / 'SNODAS'
TEMP_DIR  = DATA_ROOT / 'temp_download'

# ====== SNODAS GRID DEFINITION ======
# Full CONUS grid parameters (from SNODAS documentation)
LON_MIN = -124.733749999999
LON_MAX = -66.9420833333342
LAT_MIN =  24.9495833333335
LAT_MAX =  52.8745833333323
N_COLS  = 6935
N_ROWS  = 3351

# ====== BRB BOUNDING BOX ======
# Matching UCLA SR tile coverage (latTiles=[43,44], lonTiles=[115,116,117])
BRB_LAT = [43.0, 45.0]
BRB_LON = [-117.0, -114.0]

# ====== SNODAS PRODUCT DEFINITIONS ======
PROD_CODES = ['1025SlL00', '1025SlL01', '1034', '1036', '1038', '1039', '1044', '1050']
PROD_NAMES = ['Precip', 'SnowPrecip', 'SWE', 'Depth', 'Tsnow', 'SublimationBS', 'Melt', 'Sublimation']
N_VARS = len(PROD_CODES)

# NSIDC HTTPS base URL (no authentication required)
BASE_URL = 'https://noaadata.apps.nsidc.org/NOAA/G02158/masked/'

MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
               'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']


def build_date_list(wy: int) -> list[date]:
    """Return list of dates for a water year (Oct 1 year-1 through Sep 30 year)."""
    start = date(wy - 1, 10, 1)
    end   = date(wy, 9, 30)
    n = (end - start).days + 1
    return [start + timedelta(days=i) for i in range(n)]


def download_tar(url: str, dest: Path, timeout: int = 120) -> bool:
    """Stream-download a URL to dest. Returns True on success."""
    try:
        with requests.get(url, stream=True, timeout=timeout) as r:
            r.raise_for_status()
            with open(dest, 'wb') as f:
                for chunk in r.iter_content(chunk_size=1 << 16):
                    f.write(chunk)
        return True
    except requests.RequestException as e:
        print(f'FAILED: {e}')
        return False


def extract_tar(tar_path: Path, dest_dir: Path) -> bool:
    """Extract a tar archive to dest_dir. Returns True on success."""
    try:
        with tarfile.open(tar_path) as tf:
            tf.extractall(dest_dir)
        tar_path.unlink()
        return True
    except Exception as e:
        print(f'UNTAR FAILED: {e}')
        return False


def gunzip_file(gz_path: Path) -> Path:
    """Decompress a .gz file in-place, return path to decompressed file."""
    out_path = gz_path.with_suffix('')  # strip .gz
    with gzip.open(gz_path, 'rb') as f_in, open(out_path, 'wb') as f_out:
        shutil.copyfileobj(f_in, f_out)
    gz_path.unlink()
    return out_path


def read_snodas_binary(dat_path: Path) -> np.ndarray:
    """
    Read a SNODAS flat binary file.
    Format: int16, big-endian, N_COLS x N_ROWS stored column-major,
    transposed to [N_ROWS x N_COLS] (row = latitude, col = longitude).
    """
    raw = dat_path.read_bytes()
    D = np.frombuffer(raw, dtype='>i2')          # big-endian int16
    D = D.reshape(N_ROWS, N_COLS)                # SNODAS is row-major [rows x cols]
    return D


def load_day_cache(npz_path: Path, expected_shape: tuple) -> dict | None:
    """
    Load a cached daily .npz file.
    Returns the data dict, or None if the file is missing or has a grid size mismatch.
    """
    if not npz_path.exists():
        return None
    data = dict(np.load(npz_path, allow_pickle=True))
    # Check grid dimensions against current bounding box
    first_var = next((n for n in PROD_NAMES if n in data), None)
    if first_var is None:
        return None
    if data[first_var].shape != expected_shape:
        print(f'  cache size mismatch (expected {expected_shape}, '
              f'got {data[first_var].shape}), re-downloading')
        npz_path.unlink()
        return None
    return data


def clean_temp_dir(temp_dir: Path) -> None:
    """Remove all non-directory files from temp_dir."""
    for p in temp_dir.iterdir():
        if p.is_file():
            p.unlink()


def apply_unit_conversions(snodas: dict) -> None:
    """
    Apply SNODAS unit conversions in-place (fill value -9999 -> NaN already applied).
    Precip/SnowPrecip: raw / 10  -> mm (kg/m^2)
    SWE/Depth:         raw / 1000 -> m
    Tsnow:             no change (K)
    Sublimation/Melt:  raw / 1e5  -> m
    """
    snodas['Precip']       = snodas['Precip']       / 10.0
    snodas['SnowPrecip']   = snodas['SnowPrecip']   / 10.0
    snodas['SWE']          = snodas['SWE']           / 1000.0
    snodas['Depth']        = snodas['Depth']         / 1000.0
    # Tsnow: no scaling (already K)
    snodas['SublimationBS'] = snodas['SublimationBS'] / 1e5
    snodas['Melt']         = snodas['Melt']          / 1e5
    snodas['Sublimation']  = snodas['Sublimation']   / 1e5


def main():
    # ---- Create output directories ----
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)

    # ---- Build SNODAS coordinate arrays ----
    lon = np.linspace(LON_MIN, LON_MAX, N_COLS)
    lat = np.linspace(LAT_MAX, LAT_MIN, N_ROWS)  # north to south

    # ---- Subset indices for BRB ----
    Ix = np.where((lon >= BRB_LON[0]) & (lon <= BRB_LON[1]))[0]
    Iy = np.where((lat >= BRB_LAT[0]) & (lat <= BRB_LAT[1]))[0]
    lon_sub = lon[Ix]
    lat_sub = lat[Iy]
    ny, nx = len(Iy), len(Ix)
    expected_shape = (ny, nx)

    print(f'BRB subset: {ny} x {nx} pixels')

    # ---- Build date list ----
    all_dates = build_date_list(WY)
    n_days = len(all_dates)
    date_strs = [d.strftime('%Y-%m-%d') for d in all_dates]

    print(f'Water Year {WY}: {date_strs[0]} to {date_strs[-1]} ({n_days} days)')

    # ---- Initialize output arrays ----
    snodas = {
        'WY':      WY,
        'lat':     lat_sub,
        'lon':     lon_sub,
        'dates':   np.array([d.toordinal() for d in all_dates]),  # Python ordinal
        'datestr': np.array(date_strs),
    }
    for name in PROD_NAMES:
        snodas[name] = np.full((ny, nx, n_days), np.nan, dtype=np.float32)

    # ---- Main download loop ----
    print(f'\n=== Downloading SNODAS data for WY{WY} ===')

    for d, (dt, ds) in enumerate(zip(all_dates, date_strs)):
        yyyy, mm, dd_day = dt.year, dt.month, dt.day
        month_dir = f'{mm:02d}_{MONTH_NAMES[mm - 1]}'
        tar_name  = f'SNODAS_{yyyy:04d}{mm:02d}{dd_day:02d}.tar'
        npz_file  = OUT_DIR / f'SNODAS_BRB_{yyyy:04d}{mm:02d}{dd_day:02d}.npz'

        # ---- Check cache ----
        cached = load_day_cache(npz_file, expected_shape)
        if cached is not None:
            for name in PROD_NAMES:
                if name in cached:
                    snodas[name][:, :, d] = cached[name]
            if (d + 1) % 30 == 0:
                print(f'  [{d+1}/{n_days}] {ds} - loaded from cache')
            continue

        # ---- Build URL and download ----
        url      = f'{BASE_URL}{yyyy:04d}/{month_dir}/{tar_name}'
        tar_path = TEMP_DIR / tar_name

        print(f'  [{d+1}/{n_days}] {ds} ... ', end='', flush=True)

        if not download_tar(url, tar_path):
            continue

        if not extract_tar(tar_path, TEMP_DIR):
            continue

        # ---- Process each variable ----
        day_data: dict = {}
        for code, name in zip(PROD_CODES, PROD_NAMES):
            # Find the .dat.gz file matching this product code
            gz_files = sorted(TEMP_DIR.glob(f'*{code}*.dat.gz'))
            if not gz_files:
                continue

            # Decompress
            dat_path = gunzip_file(gz_files[0])

            # Find the .dat file (gunzip may produce a different name)
            dat_files = sorted(TEMP_DIR.glob(f'*{code}*.dat'))
            if not dat_files:
                continue

            # Read full CONUS grid, subset to BRB
            D = read_snodas_binary(dat_files[0])
            D_sub = D[np.ix_(Iy, Ix)].astype(np.float32)

            snodas[name][:, :, d] = D_sub
            day_data[name] = D_sub

            dat_files[0].unlink()

        # ---- Clean up remaining temp files ----
        clean_temp_dir(TEMP_DIR)

        # ---- Save daily cache ----
        day_data['lat'] = lat_sub
        day_data['lon'] = lon_sub
        day_data['date'] = np.array([dt.toordinal()])
        np.savez(npz_file, **day_data)

        print('OK')

    # ---- Replace fill value -9999 with NaN ----
    print('\nCleaning no-data values...')
    for name in PROD_NAMES:
        snodas[name][snodas[name] == -9999] = np.nan

    # ---- Unit conversions ----
    print('Converting units...')
    apply_unit_conversions(snodas)

    # ---- Save complete water year ----
    out_file = OUT_DIR / f'SNODAS_BRB_WY{WY}.npz'
    np.savez(out_file, **snodas)
    print(f'\nSaved: {out_file}')

    # ---- Summary ----
    print(f'\n=== Download Summary ===')
    print(f'Water Year: {WY}')
    print(f'Region: Boise River Basin ({ny} x {nx} pixels)')
    print('Variables:')
    for name in PROD_NAMES:
        arr = snodas[name]
        n_valid = int(np.sum(~np.isnan(arr)))
        n_total = arr.size
        print(f'  {name}: {100 * n_valid / n_total:.1f}% valid data')

    # Quick peek: April 1 SWE
    apr1 = date(WY, 4, 1)
    apr1_idx = min(range(n_days), key=lambda i: abs((all_dates[i] - apr1).days))
    apr1_swe   = snodas['SWE'][:, :, apr1_idx]
    apr1_depth = snodas['Depth'][:, :, apr1_idx]

    print('\nApril 1 basin statistics:')
    print(f'  Mean SWE:   {np.nanmean(apr1_swe) * 100:.1f} cm')
    print(f'  Max SWE:    {np.nanmax(apr1_swe) * 100:.1f} cm')
    print(f'  Mean Depth: {np.nanmean(apr1_depth) * 100:.1f} cm')
    print(f'  Max Depth:  {np.nanmax(apr1_depth) * 100:.1f} cm')

    size_mb = out_file.stat().st_size / 1e6
    print(f'\nOutput file: {out_file} ({size_mb:.1f} MB)')
    print('\nDone! Run plotSNODAS_BRB.py to visualize.')


if __name__ == '__main__':
    main()
