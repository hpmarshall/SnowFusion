"""
plotSnowVar.py  –  Plot a snow variable for a single date from SNODAS or UCLA data.

USAGE (as a function):
    fig, ax, im = plot_snow_var(data_struct, var_name, target_date)
    fig, ax, im = plot_snow_var(data_struct, var_name, target_date,
                                shapefile='BRB_outline.shp',
                                latlim=(43.2, 44.4), lonlim=(-116.2, -114.6))

data_struct  : dict with keys  lat, lon, dates (list/array of datetime.date or
               np.datetime64), WY, and 3-D arrays for each variable
               (shape  [nlat, nlon, ndays]).
var_name     : string – one of the SNODAS or UCLA variable names (see below).
target_date  : datetime.date | datetime.datetime | np.datetime64 | str 'YYYY-MM-DD'

SNODAS variables : SWE, Depth, Precip, SnowPrecip, Tsnow, Melt,
                   Sublimation, SublimationBS
UCLA variables   : SWE_mean, SWE_median, SWE_std, SWE_p25, SWE_p75,
                   fSCA_mean, SD_mean, SD_median, SD_std

HP Marshall, Boise State University – SnowFusion Project
"""

from __future__ import annotations

import datetime
import pathlib
import warnings

import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import numpy as np

# Optional geopandas/pyproj for shapefile support
try:
    import geopandas as gpd
    HAS_GPD = True
except ImportError:
    HAS_GPD = False

# ---------------------------------------------------------------------------
# parula approximation (MATLAB default colormap)
# ---------------------------------------------------------------------------
_PARULA_DATA = [
    [0.2081, 0.1663, 0.5292], [0.2116, 0.1898, 0.5777],
    [0.2123, 0.2138, 0.6270], [0.2081, 0.2386, 0.6771],
    [0.1959, 0.2645, 0.7279], [0.1707, 0.2919, 0.7792],
    [0.1253, 0.3242, 0.8303], [0.0591, 0.3598, 0.8683],
    [0.0117, 0.3875, 0.8820], [0.0060, 0.4086, 0.8828],
    [0.0165, 0.4266, 0.8786], [0.0329, 0.4430, 0.8720],
    [0.0498, 0.4586, 0.8641], [0.0629, 0.4737, 0.8554],
    [0.0723, 0.4887, 0.8467], [0.0779, 0.5040, 0.8384],
    [0.0793, 0.5200, 0.8312], [0.0749, 0.5375, 0.8263],
    [0.0641, 0.5570, 0.8240], [0.0562, 0.5772, 0.8228],
    [0.0553, 0.5966, 0.8199], [0.0680, 0.6137, 0.8135],
    [0.0920, 0.6287, 0.8038], [0.1135, 0.6418, 0.7913],
    [0.1302, 0.6535, 0.7771], [0.1426, 0.6643, 0.7616],
    [0.1517, 0.6746, 0.7453], [0.1614, 0.6849, 0.7281],
    [0.1738, 0.6953, 0.7103], [0.1922, 0.7060, 0.6920],
    [0.2178, 0.7168, 0.6729], [0.2494, 0.7275, 0.6526],
    [0.2837, 0.7376, 0.6309], [0.3207, 0.7468, 0.6075],
    [0.3579, 0.7552, 0.5836], [0.3951, 0.7630, 0.5595],
    [0.4308, 0.7699, 0.5352], [0.4659, 0.7761, 0.5108],
    [0.5018, 0.7813, 0.4864], [0.5395, 0.7855, 0.4619],
    [0.5778, 0.7883, 0.4372], [0.6155, 0.7898, 0.4122],
    [0.6525, 0.7901, 0.3867], [0.6881, 0.7891, 0.3608],
    [0.7214, 0.7864, 0.3348], [0.7519, 0.7823, 0.3089],
    [0.7793, 0.7771, 0.2832], [0.8036, 0.7705, 0.2578],
    [0.8250, 0.7624, 0.2325], [0.8436, 0.7526, 0.2076],
    [0.8598, 0.7409, 0.1831], [0.8736, 0.7273, 0.1593],
    [0.8853, 0.7118, 0.1361], [0.8948, 0.6943, 0.1138],
    [0.9022, 0.6748, 0.0929], [0.9077, 0.6535, 0.0738],
    [0.9113, 0.6305, 0.0571], [0.9131, 0.6059, 0.0429],
    [0.9134, 0.5800, 0.0321], [0.9121, 0.5531, 0.0253],
    [0.9094, 0.5253, 0.0230], [0.9057, 0.4970, 0.0253],
    [0.9011, 0.4683, 0.0329], [0.8960, 0.4395, 0.0466],
    [0.8908, 0.4108, 0.0668], [0.8859, 0.3824, 0.0942],
    [0.8813, 0.3548, 0.1279], [0.8771, 0.3281, 0.1670],
    [0.8729, 0.3026, 0.2099], [0.8683, 0.2787, 0.2546],
    [0.8626, 0.2569, 0.2990], [0.8543, 0.2378, 0.3404],
    [0.8424, 0.2218, 0.3756], [0.8269, 0.2085, 0.4031],
    [0.8082, 0.1971, 0.4238], [0.7864, 0.1869, 0.4393],
    [0.7625, 0.1775, 0.4511], [0.7371, 0.1686, 0.4604],
    [0.7106, 0.1598, 0.4678], [0.6833, 0.1510, 0.4739],
    [0.6554, 0.1421, 0.4790], [0.6269, 0.1332, 0.4833],
    [0.5980, 0.1243, 0.4870], [0.5688, 0.1156, 0.4900],
    [0.5392, 0.1069, 0.4924], [0.5094, 0.0985, 0.4942],
    [0.4793, 0.0904, 0.4955], [0.4490, 0.0826, 0.4963],
    [0.4184, 0.0753, 0.4965], [0.3876, 0.0685, 0.4960],
    [0.3567, 0.0622, 0.4950], [0.3256, 0.0565, 0.4934],
    [0.2943, 0.0516, 0.4910], [0.2631, 0.0476, 0.4881],
    [0.2321, 0.0446, 0.4846], [0.2016, 0.0431, 0.4806],
    [0.1722, 0.0432, 0.4763], [0.1452, 0.0453, 0.4720],
]
parula = mcolors.LinearSegmentedColormap.from_list(
    "parula", _PARULA_DATA, N=256
)

# ---------------------------------------------------------------------------
# Colormap / units lookup (matches MATLAB getVarDefaults)
# ---------------------------------------------------------------------------

def get_var_defaults(var_name: str) -> tuple[object, list | None, str]:
    """Return (colormap, clim, units) for a given variable name."""
    vl = var_name.lower()
    if vl in {"swe", "swe_mean", "swe_median", "swe_p25", "swe_p75"}:
        return parula, [0.0, 1.0], "SWE [m]"
    if vl == "swe_std":
        return "hot", [0.0, 0.3], "SWE Std Dev [m]"
    if vl in {"depth", "sd_mean", "sd_median"}:
        return "cool", [0.0, 3.0], "Snow Depth [m]"
    if vl == "sd_std":
        return "hot", [0.0, 1.0], "Snow Depth Std Dev [m]"
    if vl in {"fsca_mean", "fsca"}:
        return "gray", [0.0, 1.0], "Fractional Snow Cover [-]"
    if vl == "precip":
        return "winter", [0.0, 0.05], "Precipitation [m]"
    if vl == "snowprecip":
        return "winter", [0.0, 0.05], "Snow Precip [m WE]"
    if vl == "tsnow":
        return "jet", [250.0, 275.0], "Snow Temperature [K]"
    if vl == "melt":
        return "autumn", [0.0, 0.02], "Snowmelt [m]"
    if vl in {"sublimation", "sublimationbs"}:
        return "copper", [0.0, 0.005], "Sublimation [m]"
    return parula, None, var_name


# ---------------------------------------------------------------------------
# Date coercion helper
# ---------------------------------------------------------------------------

def _to_date(d) -> datetime.date:
    """Convert various date types to datetime.date."""
    if isinstance(d, datetime.datetime):
        return d.date()
    if isinstance(d, datetime.date):
        return d
    if isinstance(d, (np.datetime64,)):
        ts = (d - np.datetime64("1970-01-01", "D")) / np.timedelta64(1, "D")
        return (datetime.date(1970, 1, 1) + datetime.timedelta(days=int(ts)))
    if isinstance(d, str):
        return datetime.date.fromisoformat(d)
    raise TypeError(f"Cannot convert {type(d)} to date")


def _dates_as_date(dates) -> list[datetime.date]:
    """Normalise the data_struct 'dates' field to a list of datetime.date."""
    out = []
    for d in dates:
        try:
            out.append(_to_date(d))
        except Exception:
            # fall back: assume it's already usable as-is
            out.append(d)
    return out


# ---------------------------------------------------------------------------
# Main function
# ---------------------------------------------------------------------------

def plot_snow_var(
    data_struct: dict,
    var_name: str,
    target_date,
    *,
    clim: list | None = None,
    cmap=None,
    title: str = "",
    shapefile: str = "",
    fig_handle=None,
    save_fig: str = "",
    units: str = "",
    latlim: tuple | None = None,
    lonlim: tuple | None = None,
    snotel: bool = True,
    fig_size: tuple = (9, 7),
):
    """
    Plot a snow variable for a single date.

    Parameters
    ----------
    data_struct : dict
        Dictionary from getSNODAS_WY or getUCLA_SWE (Python equivalents).
        Must have keys: 'lat', 'lon', 'dates', and a 3-D array for var_name
        with shape (nlat, nlon, ndays).
    var_name : str
        Variable to plot.
    target_date : date-like
        Date to plot (datetime.date, str 'YYYY-MM-DD', np.datetime64, etc.)
    clim : [cmin, cmax] or None
        Colour limits.  Auto-scaled from data when None.
    cmap : colormap or str or None
        Matplotlib colormap.  Defaults to variable-specific choice.
    title : str
        Custom title string.  Auto-generated when empty.
    shapefile : str
        Path to a shapefile (.shp) to overlay.
    fig_handle : matplotlib.figure.Figure or None
        Existing figure to reuse.
    save_fig : str
        Filepath to save PNG.  Empty string = do not save.
    units : str
        Override units label on colour bar.
    latlim : (latmin, latmax) or None
    lonlim : (lonmin, lonmax) or None
    snotel : bool
        Attempt to load and overlay SNOTEL sites (requires getSNOTEL_BRB.py).
    fig_size : (width_inches, height_inches)

    Returns
    -------
    fig : matplotlib.figure.Figure
    ax  : matplotlib.axes.Axes
    im  : matplotlib.image.AxesImage  (the pcolormesh / imshow handle)
    """

    # ---- validate variable ------------------------------------------------
    if var_name not in data_struct:
        three_d = [k for k, v in data_struct.items()
                   if isinstance(v, np.ndarray) and v.ndim == 3]
        raise KeyError(
            f"Variable '{var_name}' not found. "
            f"Available 3-D variables:\n  " + "\n  ".join(three_d)
        )

    # ---- find date index --------------------------------------------------
    target = _to_date(target_date)
    dates = _dates_as_date(data_struct["dates"])
    deltas = [abs((d - target).days) for d in dates]
    day_idx = int(np.argmin(deltas))
    actual_date = dates[day_idx]
    if abs((actual_date - target).days) > 1:
        warnings.warn(
            f"Closest date is {actual_date} (requested {target})", stacklevel=2
        )

    # ---- extract 2-D slice -----------------------------------------------
    S = data_struct[var_name][:, :, day_idx].astype(float)

    # ---- coordinates -------------------------------------------------------
    lat = np.asarray(data_struct["lat"], dtype=float)
    lon = np.asarray(data_struct["lon"], dtype=float)

    # Flip S if lat is north-to-south (SNODAS style)
    if lat[0] > lat[-1]:
        S = np.flipud(S)
        lat = lat[::-1]

    lat_min = lat.min();  lat_max = lat.max()
    lon_min = lon.min();  lon_max = lon.max()

    latlim = latlim or (lat_min - 0.05, lat_max + 0.05)
    lonlim = lonlim or (lon_min - 0.05, lon_max + 0.05)

    # ---- colour defaults --------------------------------------------------
    def_cmap, def_clim, def_units = get_var_defaults(var_name)
    if cmap is None:
        cmap = def_cmap
    if clim is None:
        clim = def_clim
    if not units:
        units = def_units

    # auto-scale if still None
    if clim is None:
        valid = S[(S > 0) & np.isfinite(S)]
        clim = [0.0, float(np.percentile(valid, 98))] if valid.size else [0.0, 1.0]

    # ---- masked array (zeros + NaN = transparent) -------------------------
    S_masked = np.ma.masked_where((S == 0) | ~np.isfinite(S), S)

    # ---- figure ------------------------------------------------------------
    if fig_handle is not None:
        fig = fig_handle
        fig.clf()
    else:
        fig = plt.figure(figsize=fig_size, facecolor="white")

    ax = fig.add_subplot(111)

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
    ax.set_xlabel("Longitude", fontsize=12, fontweight="bold")
    ax.set_ylabel("Latitude", fontsize=12, fontweight="bold")
    ax.tick_params(labelsize=11)
    ax.set_aspect("equal")

    # colorbar
    cb = fig.colorbar(im, ax=ax, location="bottom", pad=0.08, fraction=0.04)
    cb.set_label(units, fontsize=13, fontweight="bold")
    cb.ax.tick_params(labelsize=11)

    # ---- shapefile overlay ------------------------------------------------
    if shapefile:
        shp_path = pathlib.Path(shapefile)
        if shp_path.exists() and HAS_GPD:
            gdf = gpd.read_file(shp_path)
            # reproject to WGS-84 if needed
            if gdf.crs and gdf.crs.to_epsg() != 4326:
                gdf = gdf.to_crs(epsg=4326)
            gdf.boundary.plot(ax=ax, color=(0.3, 0.3, 0.3), linewidth=2.5, zorder=3)
        elif shp_path.exists() and not HAS_GPD:
            warnings.warn("geopandas not available; shapefile overlay skipped.")

    # ---- SNOTEL overlay ---------------------------------------------------
    if snotel:
        _try_overlay_snotel(ax, latlim, lonlim)

    # ---- title ------------------------------------------------------------
    if not title:
        wy = data_struct.get("WY", "")
        wy_str = f"WY{wy}" if wy else ""
        if any(k in data_struct for k in ("SWE_mean", "fSCA_mean", "SD_mean")):
            src_name = "UCLA SWE"
        else:
            src_name = "SNODAS"
        title = f"{src_name} {var_name} – {actual_date}  {wy_str}"

    ax.set_title(title, fontsize=16, fontweight="bold")
    fig.tight_layout()

    # ---- save -------------------------------------------------------------
    if save_fig:
        fig.savefig(save_fig, dpi=200, bbox_inches="tight")
        print(f"Figure saved to {save_fig}")

    return fig, ax, im


# ---------------------------------------------------------------------------
# SNOTEL helper
# ---------------------------------------------------------------------------

def _try_overlay_snotel(ax, latlim, lonlim):
    """Attempt to import getSNOTEL_BRB and overlay sites on ax."""
    try:
        import sys, pathlib as _pl
        _script_dir = _pl.Path(__file__).parent
        if str(_script_dir) not in sys.path:
            sys.path.insert(0, str(_script_dir))
        from getSNOTEL_BRB import getSNOTEL_BRB
        shp_path = _script_dir.parent / "SNOTEL" / "IDDCO_2020_automated_sites.shp"
        snotel = getSNOTEL_BRB(shp_path, lat_lim=latlim, lon_lim=lonlim)
        if snotel and snotel.get("n_stations", 0) > 0:
            ax.plot(
                snotel["lon"], snotel["lat"],
                "r*", markersize=10, markeredgecolor="darkred",
                zorder=5, label="SNOTEL",
            )
    except Exception:
        pass  # silently skip if module or data not available


# ---------------------------------------------------------------------------
# CLI convenience
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse, pickle

    parser = argparse.ArgumentParser(description="Plot a snow variable for a single date.")
    parser.add_argument("data_file", help="Path to pickled data dict (.pkl)")
    parser.add_argument("var_name", help="Variable name to plot")
    parser.add_argument("date", help="Date YYYY-MM-DD")
    parser.add_argument("--shapefile", default="", help="Path to .shp overlay")
    parser.add_argument("--save", default="", help="Output PNG path")
    args = parser.parse_args()

    with open(args.data_file, "rb") as fh:
        data = pickle.load(fh)

    fig, ax, im = plot_snow_var(
        data, args.var_name, args.date,
        shapefile=args.shapefile,
        save_fig=args.save,
    )
    plt.show()
