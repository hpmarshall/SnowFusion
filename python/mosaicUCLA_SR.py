"""
mosaicUCLA_SR.py - Read and mosaic WUS UCLA Snow Reanalysis tiles

Reads multiple 1-deg x 1-deg NetCDF tiles and mosaics them into a
continuous grid covering the region of interest.

NOTE: The UCLA SR dataset uses separate files for different variables:
    *_SWE_SCA_POST.nc  -> contains SWE_Post and SCA_Post
    *_SD_POST.nc       -> contains SD_Post

NetCDF dimension ordering:
    [225 x 225 x 5 x 366] = [Latitude x Longitude x ensemble x day]
    - dim 0 corresponds to Latitude
    - dim 1 corresponds to Longitude
    So data is already [lat x lon x ens x day] — no transpose needed.

This function uses coordinate-based placement: each tile's lat/lon
arrays are read and matched to the mosaic grid, avoiding any
assumptions about tile ordering.

HP Marshall, Boise State University, April 2026
"""

from pathlib import Path

import numpy as np
import netCDF4 as nc


# ---------------------------------------------------------------------------
# Helper: find variable name (case-insensitive, partial-match fallback)
# ---------------------------------------------------------------------------

def _find_var(var_names, candidates):
    """Return the first name in var_names that matches any candidate.

    Tries exact case-insensitive match first, then substring match.

    Parameters
    ----------
    var_names  : list of str — variable names present in the file
    candidates : list of str — preferred names, in priority order

    Returns
    -------
    str : matched variable name, or candidates[0] with a warning
    """
    lower_names = [v.lower() for v in var_names]

    # Exact case-insensitive match
    for cand in candidates:
        try:
            idx = lower_names.index(cand.lower())
            return var_names[idx]
        except ValueError:
            pass

    # Substring match
    for cand in candidates:
        for i, lname in enumerate(lower_names):
            if cand.lower() in lname:
                return var_names[i]

    print(f"  WARNING: Could not find variable matching: {', '.join(candidates)}")
    return candidates[0]


# ---------------------------------------------------------------------------
# Helper: map tile coordinate vector to mosaic index array
# ---------------------------------------------------------------------------

def _find_coord_idx(tile_coords, mosaic_coords, tol=1e-6):
    """For each coordinate in tile_coords, return its index in mosaic_coords.

    Parameters
    ----------
    tile_coords   : array-like, shape (n,)
    mosaic_coords : array-like, shape (M,)
    tol           : float — tolerance for coordinate matching

    Returns
    -------
    np.ndarray of int, shape (n,) — indices into mosaic_coords
    """
    tile_coords   = np.asarray(tile_coords)
    mosaic_coords = np.asarray(mosaic_coords)

    idx = np.empty(len(tile_coords), dtype=int)
    for i, c in enumerate(tile_coords):
        dist = np.abs(mosaic_coords - c)
        min_i = int(np.argmin(dist))
        if dist[min_i] < tol:
            idx[i] = min_i
        else:
            raise ValueError(
                f"Coordinate {c:.6f} not found in mosaic grid "
                f"(nearest: {mosaic_coords[min_i]:.6f}, dist: {dist[min_i]:.6f})"
            )
    return idx


# ---------------------------------------------------------------------------
# Helper: glob for a tile file with optional water-year qualifier
# ---------------------------------------------------------------------------

def _find_tile_file(data_dir, tile_str, wy_str, suffix):
    """Return the first matching Path for a tile file, or None.

    Searches first for '*<tile>*<wy>*<suffix>', then falls back to
    '*<tile>*<suffix>' when the water-year qualifier yields no match.
    """
    data_dir = Path(data_dir)
    hits = sorted(data_dir.glob(f"*{tile_str}*{wy_str}*{suffix}"))
    if not hits:
        hits = sorted(data_dir.glob(f"*{tile_str}*{suffix}"))
    return hits[0] if hits else None


# ---------------------------------------------------------------------------
# Main function
# ---------------------------------------------------------------------------

def mosaicUCLA_SR(data_dir, wy_str, lat_tiles, lon_tiles):
    """Read and mosaic WUS UCLA Snow Reanalysis NetCDF tiles.

    Parameters
    ----------
    data_dir  : str or Path
        Directory containing downloaded .nc files.
    wy_str    : str
        Water year string, e.g. 'WY2020_21'.
    lat_tiles : list/array of int
        Tile lower-left latitudes, e.g. [43, 44].
    lon_tiles : list/array of int
        Tile lower-left west longitudes, e.g. [115, 116, 117].

    Returns
    -------
    lat  : np.ndarray, shape (M,)
        Latitude vector (degrees N, descending = north to south).
    lon  : np.ndarray, shape (N,)
        Longitude vector (degrees E, ascending = west to east).
    SWE  : np.ndarray, shape (M, N, 5, nDays)
        Snow water equivalent [m].
    fSCA : np.ndarray, shape (M, N, 5, nDays)
        Fractional snow-covered area [0-1].
    SD   : np.ndarray, shape (M, N, 5, nDays)
        Snow depth [m].

    Ensemble stats (axis 2):
        0=mean, 1=std, 2=25th pctl, 3=50th pctl (median), 4=75th pctl
    """
    data_dir  = Path(data_dir)
    lat_tiles = list(lat_tiles)
    lon_tiles = list(lon_tiles)

    # ------------------------------------------------------------------
    # Probe the first tile to discover variable names and dimensions
    # ------------------------------------------------------------------
    test_tile = f"N{lat_tiles[0]}_0W{lon_tiles[0]}_0"
    test_swe_file = _find_tile_file(data_dir, test_tile, wy_str, "SWE_SCA_POST*.nc")
    test_sd_file  = _find_tile_file(data_dir, test_tile, wy_str, "SD_POST*.nc")

    has_swe = test_swe_file is not None
    has_sd  = test_sd_file  is not None

    if not has_swe and not has_sd:
        raise FileNotFoundError(
            f"No NetCDF files found for tile {test_tile} in {data_dir}\n"
            "Run getUCLA_SR_BRB first."
        )

    # Discover variable names from the probe file
    if has_swe:
        probe_file = test_swe_file
        with nc.Dataset(probe_file) as ds:
            var_names = list(ds.variables.keys())
        print(f"SWE/SCA file: {probe_file.name}")
        print(f"  Variables: {', '.join(var_names)}")
        swe_var  = _find_var(var_names, ["SWE_Post", "SWE", "swe"])
        fsca_var = _find_var(var_names, ["SCA_Post", "fSCA", "fsca", "SCA"])
    else:
        probe_file = test_sd_file
        with nc.Dataset(probe_file) as ds:
            var_names = list(ds.variables.keys())
        print(f"SD file: {probe_file.name}")
        print(f"  Variables: {', '.join(var_names)}")
        swe_var  = None
        fsca_var = None

    lat_var = _find_var(var_names, ["Latitude",  "lat", "latitude"])
    lon_var = _find_var(var_names, ["Longitude", "lon", "longitude"])

    # Discover SD variable names (may differ from SWE file)
    if has_sd:
        with nc.Dataset(test_sd_file) as ds:
            sd_var_names = list(ds.variables.keys())
        print(f"SD file: {test_sd_file.name}")
        print(f"  Variables: {', '.join(sd_var_names)}")
        sd_var     = _find_var(sd_var_names, ["SD_Post", "SD", "sd", "snow_depth"])
        sd_lat_var = _find_var(sd_var_names, ["Latitude",  "lat", "latitude"])
        sd_lon_var = _find_var(sd_var_names, ["Longitude", "lon", "longitude"])
    else:
        sd_var     = None
        sd_lat_var = None
        sd_lon_var = None

    # Per-tile dimensions from probe data
    with nc.Dataset(probe_file) as ds:
        probe_data = ds.variables[swe_var if has_swe else sd_var][:]
        # Shape: [days, ensemble, lat, lon]
        n_days = probe_data.shape[0]
        n_ens  = probe_data.shape[1]
        tile_lat_probe = ds.variables[lat_var][:]
        tile_lon_probe = ds.variables[lon_var][:]

    n_lat_pix = len(tile_lat_probe)
    n_lon_pix = len(tile_lon_probe)
    print(
        f"Per-tile: {n_lon_pix} lon x {n_lat_pix} lat "
        f"x {n_ens} ensemble x {n_days} days"
    )
    if has_swe:
        print(f"SWE var: {swe_var}, SCA var: {fsca_var}")
    if has_sd:
        print(f"SD var:  {sd_var}")

    # ------------------------------------------------------------------
    # Build the full mosaic coordinate vectors
    # ------------------------------------------------------------------
    all_lats = []
    all_lons = []

    for ilat in lat_tiles:
        for ilon in lon_tiles:
            tile_str = f"N{ilat}_0W{ilon}_0"
            f = _find_tile_file(
                data_dir, tile_str, wy_str,
                "SWE_SCA_POST*.nc" if has_swe else "SD_POST*.nc"
            )
            if f is None:
                continue
            with nc.Dataset(f) as ds:
                all_lats.append(np.asarray(ds.variables[lat_var][:]).ravel())
                all_lons.append(np.asarray(ds.variables[lon_var][:]).ravel())

    all_lats = np.concatenate(all_lats)
    all_lons = np.concatenate(all_lons)

    # Latitude descending (north to south) for natural display
    lat_vec = np.sort(np.unique(all_lats))[::-1]
    # Longitude ascending (west to east)
    lon_vec = np.sort(np.unique(all_lons))

    total_lat_pix = len(lat_vec)
    total_lon_pix = len(lon_vec)
    print(f"Mosaic grid: {total_lat_pix} lat x {total_lon_pix} lon pixels")

    # ------------------------------------------------------------------
    # Allocate output arrays: [lat, lon, ensemble, day]
    # ------------------------------------------------------------------
    SWE  = np.full((total_lat_pix, total_lon_pix, n_ens, n_days), np.nan, dtype=np.float32)
    fSCA = np.full((total_lat_pix, total_lon_pix, n_ens, n_days), np.nan, dtype=np.float32)
    SD   = np.full((total_lat_pix, total_lon_pix, n_ens, n_days), np.nan, dtype=np.float32)

    # ------------------------------------------------------------------
    # Read and place each tile using coordinate-based indexing
    # ------------------------------------------------------------------
    tol = 1e-6

    for ilat in lat_tiles:
        for ilon in lon_tiles:
            tile_str = f"N{ilat}_0W{ilon}_0"

            # --- SWE and SCA from SWE_SCA_POST file ---
            if has_swe:
                swe_f = _find_tile_file(data_dir, tile_str, wy_str, "SWE_SCA_POST*.nc")
                if swe_f is not None:
                    print(f"  Reading SWE/SCA: {swe_f.name}")
                    with nc.Dataset(swe_f) as ds:
                        tile_lat  = np.asarray(ds.variables[lat_var][:])
                        tile_lon  = np.asarray(ds.variables[lon_var][:])
                        tile_swe  = np.asarray(ds.variables[swe_var][:])   # [days,ens,lat,lon]
                        tile_fsca = np.asarray(ds.variables[fsca_var][:])

                    # File is (day, ens, lon, lat); transpose to (lat, lon, ens, day)
                    tile_swe  = tile_swe.transpose(3, 2, 1, 0)
                    tile_fsca = tile_fsca.transpose(3, 2, 1, 0)

                    lat_idx = _find_coord_idx(tile_lat, lat_vec, tol)
                    lon_idx = _find_coord_idx(tile_lon, lon_vec, tol)

                    SWE [np.ix_(lat_idx, lon_idx)]  = tile_swe
                    fSCA[np.ix_(lat_idx, lon_idx)]  = tile_fsca
                else:
                    print(f"  WARNING: No SWE_SCA file for tile {tile_str}")

            # --- SD from SD_POST file ---
            if has_sd:
                sd_f = _find_tile_file(data_dir, tile_str, wy_str, "SD_POST*.nc")
                if sd_f is not None:
                    print(f"  Reading SD:      {sd_f.name}")
                    with nc.Dataset(sd_f) as ds:
                        tile_lat = np.asarray(ds.variables[sd_lat_var][:])
                        tile_lon = np.asarray(ds.variables[sd_lon_var][:])
                        tile_sd  = np.asarray(ds.variables[sd_var][:])   # [days,ens,lat,lon]

                    tile_sd = tile_sd.transpose(3, 2, 1, 0)

                    lat_idx = _find_coord_idx(tile_lat, lat_vec, tol)
                    lon_idx = _find_coord_idx(tile_lon, lon_vec, tol)

                    SD[np.ix_(lat_idx, lon_idx)] = tile_sd
                else:
                    print(f"  WARNING: No SD file for tile {tile_str}")

    print(f"Mosaic complete: {len(lat_vec)} x {len(lon_vec)} pixels")
    return lat_vec, lon_vec, SWE, fSCA, SD


if __name__ == "__main__":
    data_dir  = Path("/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR")
    wy_str    = "WY2020_21"
    lat_tiles = [43, 44]
    lon_tiles = [115, 116, 117]

    lat, lon, SWE, fSCA, SD = mosaicUCLA_SR(data_dir, wy_str, lat_tiles, lon_tiles)
    print(f"lat shape : {lat.shape},  range [{lat.min():.4f}, {lat.max():.4f}]")
    print(f"lon shape : {lon.shape},  range [{lon.min():.4f}, {lon.max():.4f}]")
    print(f"SWE shape : {SWE.shape}")
    print(f"fSCA shape: {fSCA.shape}")
    print(f"SD shape  : {SD.shape}")
