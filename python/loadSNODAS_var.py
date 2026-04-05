"""
loadSNODAS_var.py - Load a single variable from a SNODAS water year .mat file

USAGE:
    data_root = Path('/Users/hpmarshall/DATA_DRIVE/SnowFusion')
    data, lat, lon = loadSNODAS_var(
        data_root / 'SNODAS/SNODAS_BRB_WY2024.mat', 'SWE'
    )

HP Marshall, Boise State University, April 2026
"""

from pathlib import Path

import numpy as np
import scipy.io


def loadSNODAS_var(mat_file, var_name):
    """Load a single variable from a SNODAS water-year .mat file.

    The .mat file may be either a full water-year file (containing a top-level
    'Snodas' struct) or a single-day file (variables at the top level).

    Parameters
    ----------
    mat_file : str or Path
        Path to the .mat file created by getSNODAS_BRB.m.
    var_name : str
        Variable name to load. Typical options:
        'Precip', 'SnowPrecip', 'SWE', 'Depth',
        'Tsnow', 'SublimationBS', 'Melt', 'Sublimation'.

    Returns
    -------
    data : np.ndarray, shape (nLat, nLon, nDays)
        Requested variable with units converted (as stored in the .mat file).
    lat  : np.ndarray
        Latitude vector (north to south).
    lon  : np.ndarray
        Longitude vector (west to east).

    Raises
    ------
    KeyError
        If var_name is not found in the file.
    """
    mat_file = Path(mat_file)

    # scipy.io.loadmat uses squeeze_me and struct_as_record for cleaner access.
    R = scipy.io.loadmat(str(mat_file), squeeze_me=True, struct_as_record=False)

    # Remove scipy meta-keys
    user_keys = [k for k in R.keys() if not k.startswith("__")]

    if "Snodas" in user_keys:
        # Full water-year file: data lives inside the 'Snodas' struct
        S = R["Snodas"]
        available = [f for f in S._fieldnames]
        if var_name not in available:
            raise KeyError(
                f'Variable "{var_name}" not found. '
                f"Available: {', '.join(available)}"
            )
        data = np.asarray(getattr(S, var_name))
        lat  = np.asarray(S.lat).ravel()
        lon  = np.asarray(S.lon).ravel()
    else:
        # Single-day file: variables are at the top level
        if var_name not in user_keys:
            raise KeyError(
                f'Variable "{var_name}" not found. '
                f"Available: {', '.join(user_keys)}"
            )
        data = np.asarray(R[var_name])
        lat  = np.asarray(R["lat"]).ravel()
        lon  = np.asarray(R["lon"]).ravel()

    return data, lat, lon


if __name__ == "__main__":
    import sys

    if len(sys.argv) >= 3:
        mat_file = Path(sys.argv[1])
        var_name = sys.argv[2]
    else:
        mat_file = Path(
            "/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS/SNODAS_BRB_WY2024.mat"
        )
        var_name = "SWE"

    data, lat, lon = loadSNODAS_var(mat_file, var_name)
    print(f"Loaded '{var_name}' from {mat_file.name}")
    print(f"  data shape : {data.shape}")
    print(f"  lat  range : [{lat.min():.4f}, {lat.max():.4f}]  ({len(lat)} pts)")
    print(f"  lon  range : [{lon.min():.4f}, {lon.max():.4f}]  ({len(lon)} pts)")
    print(f"  data range : [{np.nanmin(data):.4f}, {np.nanmax(data):.4f}]")
