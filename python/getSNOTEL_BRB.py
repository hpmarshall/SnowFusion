"""
getSNOTEL_BRB.py - Load SNOTEL sites from shapefile, optionally filtered by bounding box

HP Marshall, Boise State University
SnowFusion Project, April 2026
"""

from pathlib import Path
import numpy as np
import geopandas as gpd


def getSNOTEL_BRB(
    shp_path,
    lat_lim=(-np.inf, np.inf),
    lon_lim=(-np.inf, np.inf),
):
    """Load SNOTEL sites from shapefile, optionally filtered by a bounding box.

    Coordinates are read from the DBF attributes (decimal degrees, WGS84).

    Parameters
    ----------
    shp_path : str or Path
        Path to the SNOTEL shapefile (e.g. IDDCO_2020_automated_sites.shp).
    lat_lim : tuple of float, optional
        (lat_min, lat_max) bounding box latitude limits.
        Defaults to (-inf, inf) — no filtering.
    lon_lim : tuple of float, optional
        (lon_min, lon_max) bounding box longitude limits.
        Defaults to (-inf, inf) — no filtering.

    Returns
    -------
    dict with keys:
        name        : list of str  — station names
        site_num    : np.ndarray   — NRCS site numbers (Ntwk_Id)
        lat         : np.ndarray   — latitudes  (decimal degrees N)
        lon         : np.ndarray   — longitudes (decimal degrees E, negative = W)
        elev_ft     : np.ndarray   — elevations (feet)
        n_stations  : int          — number of stations after filtering
    """
    shp_path = Path(shp_path)

    # Read shapefile; DBF attributes carry precise decimal-degree lat/lon
    gdf = gpd.read_file(shp_path)

    # Extract attribute columns
    names    = gdf["sta_nm"].tolist()
    site_num = gdf["Ntwk_Id"].to_numpy(dtype=float)
    lats     = gdf["lat"].to_numpy(dtype=float)
    lons     = gdf["lon"].to_numpy(dtype=float)
    elevs    = gdf["elev"].to_numpy(dtype=float)

    # Filter by bounding box
    keep = (
        (lats >= lat_lim[0]) & (lats <= lat_lim[1]) &
        (lons >= lon_lim[0]) & (lons <= lon_lim[1])
    )

    snotel = {
        "name":       [n for n, k in zip(names, keep) if k],
        "site_num":   site_num[keep],
        "lat":        lats[keep],
        "lon":        lons[keep],
        "elev_ft":    elevs[keep],
        "n_stations": int(keep.sum()),
    }

    return snotel


if __name__ == "__main__":
    import sys

    shp = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNOTEL/IDDCO_2020_automated_sites.shp"
    )

    # Example: filter to the Boise River Basin rough bounding box
    snotel = getSNOTEL_BRB(
        shp,
        lat_lim=(43.0, 45.0),
        lon_lim=(-117.5, -114.5),
    )

    print(f"Loaded {snotel['n_stations']} SNOTEL stations")
    for i in range(snotel["n_stations"]):
        print(
            f"  {snotel['name'][i]:40s}  "
            f"lat={snotel['lat'][i]:.4f}  "
            f"lon={snotel['lon'][i]:.4f}  "
            f"elev={snotel['elev_ft'][i]:.0f} ft"
        )
