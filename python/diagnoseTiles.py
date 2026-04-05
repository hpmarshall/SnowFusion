"""
diagnoseTiles.py - Diagnostic script to check UCLA SR tile coordinate ordering

Run from any directory; paths are configured at the top of the script.

HP Marshall, Boise State University, April 2026
"""

from pathlib import Path

import numpy as np
import netCDF4 as nc


# ---------------------------------------------------------------------------
# Configuration — edit these to match your environment
# ---------------------------------------------------------------------------
DATA_DIR  = Path("/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR")
WY_STR    = "WY2020_21"
LAT_TILES = [43, 44]
LON_TILES = [115, 116, 117]

# Day index for the diagnostic SWE slice (0-based; 182 = ~Apr 1 in a 365-day year)
DAY_IDX = 182


# ---------------------------------------------------------------------------
# Helper: find the first matching file or return None
# ---------------------------------------------------------------------------
def _find(data_dir, pattern):
    hits = sorted(data_dir.glob(pattern))
    return hits[0] if hits else None


# ---------------------------------------------------------------------------
# Main diagnostic routine
# ---------------------------------------------------------------------------
def diagnose_tiles(data_dir=DATA_DIR, wy_str=WY_STR, lat_tiles=LAT_TILES,
                   lon_tiles=LON_TILES, day_idx=DAY_IDX):
    """Print coordinate and data diagnostics for each UCLA SR tile.

    Parameters
    ----------
    data_dir  : Path — directory containing downloaded .nc files
    wy_str    : str  — water year string, e.g. 'WY2020_21'
    lat_tiles : list of int — tile lower-left latitudes
    lon_tiles : list of int — tile lower-left west longitudes
    day_idx   : int — 0-based day index for the SWE diagnostic slice
    """
    data_dir = Path(data_dir)

    print("=== Tile Coordinate Diagnostics ===\n")

    for ilat in lat_tiles:
        for ilon in lon_tiles:
            tile_str = f"N{ilat}_0W{ilon}_0"

            # Find SWE_SCA file
            f = _find(data_dir, f"*{tile_str}*{wy_str}*SWE_SCA_POST*.nc")
            if f is None:
                f = _find(data_dir, f"*{tile_str}*SWE_SCA_POST*.nc")
            if f is None:
                continue

            with nc.Dataset(f) as ds:
                lat = np.asarray(ds.variables["Latitude"][:])
                lon = np.asarray(ds.variables["Longitude"][:])

                # Full SWE array shape: [lat, lon, ensemble, day]
                swe_var = ds.variables["SWE_Post"]
                swe_shape = swe_var.shape
                # Read a single ensemble-mean slice for day_idx
                swe_full  = np.asarray(swe_var[:])          # [lat, lon, ens, day]
                swe_slice = swe_full[:, :, 0, day_idx]      # [lat, lon]

            print(f"Tile: {tile_str}")
            print(f"  File: {f.name}")

            # --- Latitude diagnostics ---
            print(
                f"  Lat: size={lat.shape}, "
                f"range=[{lat.min():.4f}, {lat.max():.4f}], "
                f"first3=[{lat[0]:.4f} {lat[1]:.4f} {lat[2]:.4f}], "
                f"last3=[{lat[-3]:.4f} {lat[-2]:.4f} {lat[-1]:.4f}]"
            )

            # --- Longitude diagnostics ---
            print(
                f"  Lon: size={lon.shape}, "
                f"range=[{lon.min():.4f}, {lon.max():.4f}], "
                f"first3=[{lon[0]:.4f} {lon[1]:.4f} {lon[2]:.4f}], "
                f"last3=[{lon[-3]:.4f} {lon[-2]:.4f} {lon[-1]:.4f}]"
            )

            lat_ascending = bool(np.all(np.diff(lat) > 0))
            lon_ascending = bool(np.all(np.diff(lon) > 0))
            print(f"  Lat ascending? {lat_ascending}   Lon ascending? {lon_ascending}")

            # --- SWE slice diagnostics ---
            n_nan    = int(np.sum(np.isnan(swe_slice)))
            n_total  = swe_slice.size
            nan_pct  = 100.0 * n_nan / n_total
            swe_mean = float(np.nanmean(swe_slice))

            print(f"  SWE_Post size: {swe_shape}  (raw read)")
            print(f"  SWE slice[:,:,0,{day_idx}] size: {swe_slice.shape}")
            print(f"  SWE slice: mean={swe_mean:.4f}, NaN%={nan_pct:.1f}%")

            # Corner values help confirm lat/lon axis assignment
            print(
                f"  Corner values  SWE[0,0]={swe_slice[0,0]:.4f}, "
                f"SWE[-1,0]={swe_slice[-1,0]:.4f}, "
                f"SWE[0,-1]={swe_slice[0,-1]:.4f}, "
                f"SWE[-1,-1]={swe_slice[-1,-1]:.4f}"
            )
            print()

    # ------------------------------------------------------------------
    # Check that adjacent tiles share matching edge coordinates
    # ------------------------------------------------------------------
    print("=== Check: Do adjacent tiles have matching edge coordinates? ===")

    # East-West neighbours: W116 right edge vs W115 left edge
    f116 = _find(data_dir, f"*N43_0W116_0*{wy_str}*SWE_SCA_POST*.nc")
    if f116 is None:
        f116 = _find(data_dir, "*N43_0W116_0*SWE_SCA_POST*.nc")
    f115 = _find(data_dir, f"*N43_0W115_0*{wy_str}*SWE_SCA_POST*.nc")
    if f115 is None:
        f115 = _find(data_dir, "*N43_0W115_0*SWE_SCA_POST*.nc")

    if f116 and f115:
        with nc.Dataset(f116) as ds:
            lon116 = np.asarray(ds.variables["Longitude"][:])
        with nc.Dataset(f115) as ds:
            lon115 = np.asarray(ds.variables["Longitude"][:])

        print(f"  W116 lon range: [{lon116.min():.4f}, {lon116.max():.4f}]")
        print(f"  W115 lon range: [{lon115.min():.4f}, {lon115.max():.4f}]")
        print(f"  W116 right edge (last lon): {lon116[-1]:.4f}")
        print(f"  W115 left  edge (first lon): {lon115[0]:.4f}")
        print(f"  Gap between tiles: {lon115[0] - lon116[-1]:.6f} deg")
    else:
        print("  (W116 or W115 tile not found — skipping E-W edge check)")

    # North-South neighbours: N43 top edge vs N44 bottom edge
    f43 = _find(data_dir, f"*N43_0W116_0*{wy_str}*SWE_SCA_POST*.nc")
    if f43 is None:
        f43 = _find(data_dir, "*N43_0W116_0*SWE_SCA_POST*.nc")
    f44 = _find(data_dir, f"*N44_0W116_0*{wy_str}*SWE_SCA_POST*.nc")
    if f44 is None:
        f44 = _find(data_dir, "*N44_0W116_0*SWE_SCA_POST*.nc")

    if f43 and f44:
        with nc.Dataset(f43) as ds:
            lat43 = np.asarray(ds.variables["Latitude"][:])
        with nc.Dataset(f44) as ds:
            lat44 = np.asarray(ds.variables["Latitude"][:])

        print(f"  N43 lat range: [{lat43.min():.4f}, {lat43.max():.4f}]")
        print(f"  N44 lat range: [{lat44.min():.4f}, {lat44.max():.4f}]")
        print(f"  N43 top edge    (max lat): {lat43.max():.4f}")
        print(f"  N44 bottom edge (min lat): {lat44.min():.4f}")
    else:
        print("  (N43 or N44 tile not found — skipping N-S edge check)")

    print("\nDone.")


if __name__ == "__main__":
    diagnose_tiles()
