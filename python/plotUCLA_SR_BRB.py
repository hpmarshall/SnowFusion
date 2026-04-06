"""
plotUCLA_SR_BRB.py
Visualize WUS UCLA Snow Reanalysis data over the Boise River Basin (BRB).

Reads downloaded NetCDF tiles, mosaics them into a continuous grid, clips to
the BRB shapefile for time series, and generates 6 figures:

    1. SWE map for target date
    2. Fractional snow-covered area (fSCA) map
    3. Snow Depth map (if SD_POST files are present)
    4. 3-panel summary (SWE, fSCA, Depth or SWE uncertainty)
    5. Time series of basin-mean SWE (ensemble mean +/- 1-sigma)
    6. SWE Uncertainty (ensemble std) map

Coordinate options
    use_utm=True  -> UTM Zone 11N [km] (default)
    use_utm=False -> geographic [deg]

HP Marshall, Boise State University
SnowFusion Project
Created: April 2026
"""

from __future__ import annotations

import sys
import glob
from pathlib import Path
from datetime import datetime, timedelta

import numpy as np
import netCDF4 as nc
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import geopandas as gpd
from pyproj import Transformer
from matplotlib.path import Path as MPath

# ── local helper (lives next to this file) ─────────────────────────────────
sys.path.insert(0, str(Path(__file__).parent))
from getSNOTEL_BRB import getSNOTEL_BRB


# ===========================================================================
# Colormaps
# ===========================================================================

def _parula_cmap() -> mcolors.LinearSegmentedColormap:
    """Close approximation of MATLAB's parula colormap."""
    _data = [
        (0.2081, 0.1663, 0.5292),
        (0.2116, 0.1898, 0.5777),
        (0.2123, 0.2138, 0.6270),
        (0.2081, 0.2386, 0.6771),
        (0.1959, 0.2645, 0.7279),
        (0.1707, 0.2919, 0.7792),
        (0.1253, 0.3242, 0.8303),
        (0.0591, 0.3598, 0.8683),
        (0.0156, 0.3929, 0.8752),
        (0.0098, 0.4259, 0.8533),
        (0.0625, 0.4584, 0.8244),
        (0.1312, 0.4903, 0.7994),
        (0.1938, 0.5217, 0.7760),
        (0.2545, 0.5530, 0.7510),
        (0.3167, 0.5844, 0.7240),
        (0.3815, 0.6157, 0.6946),
        (0.4495, 0.6464, 0.6622),
        (0.5215, 0.6760, 0.6263),
        (0.5985, 0.7035, 0.5860),
        (0.6809, 0.7271, 0.5396),
        (0.7680, 0.7451, 0.4864),
        (0.8567, 0.7556, 0.4265),
        (0.9430, 0.7574, 0.3613),
        (0.9938, 0.7836, 0.3010),
        (0.9950, 0.8439, 0.2840),
        (0.9832, 0.9067, 0.2912),
        (0.9769, 0.9839, 0.0805),
    ]
    return mcolors.LinearSegmentedColormap.from_list("parula", _data)


PARULA = _parula_cmap()


def _white_parula_cmap(n: int = 255) -> mcolors.ListedColormap:
    """White for zero, then parula gradient — mirrors MATLAB's [1 1 1; parula(255)]."""
    parula_colors = PARULA(np.linspace(0, 1, n))
    white = np.array([[1.0, 1.0, 1.0, 1.0]])
    colors = np.vstack([white, parula_colors])
    cmap = mcolors.ListedColormap(colors)
    cmap.set_bad(alpha=0)
    return cmap


# ===========================================================================
# mosaic helper (Python translation of mosaicUCLA_SR.m)
# ===========================================================================

def _find_var(var_names: list[str], candidates: list[str]) -> str:
    """Return the first candidate name found (case-insensitive) in var_names."""
    lower_names = [v.lower() for v in var_names]
    for cand in candidates:
        try:
            idx = lower_names.index(cand.lower())
            return var_names[idx]
        except ValueError:
            pass
    # Partial match fallback
    for cand in candidates:
        for i, vn in enumerate(lower_names):
            if cand.lower() in vn:
                return var_names[i]
    import warnings
    warnings.warn(f"Could not find variable matching: {candidates}")
    return candidates[0]


def _find_tile_files(data_dir: Path, tile_str: str, wy_str: str,
                     suffix: str) -> list[Path]:
    """Find NC files matching tile + WY string + suffix pattern."""
    patterns = [
        str(data_dir / f"*{tile_str}*{wy_str}*{suffix}*.nc"),
        str(data_dir / f"*{tile_str}*{suffix}*.nc"),
    ]
    for pat in patterns:
        found = sorted(glob.glob(pat))
        if found:
            return [Path(f) for f in found]
    return []


def mosaic_ucla_sr(
    data_dir: str | Path,
    wy_str: str,
    lat_tiles: list[int],
    lon_tiles: list[int],
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Read and mosaic WUS UCLA Snow Reanalysis NetCDF tiles.

    Parameters
    ----------
    data_dir  : directory containing downloaded .nc files
    wy_str    : water year string, e.g. 'WY2020_21'
    lat_tiles : list of tile lower-left latitudes, e.g. [43, 44]
    lon_tiles : list of tile lower-left west longitudes, e.g. [115, 116, 117]

    Returns
    -------
    lat  : (M,) latitude vector   [deg N, descending = north to south]
    lon  : (N,) longitude vector  [deg E, ascending  = west to east]
    SWE  : (M, N, 5, nDays)  snow water equivalent [m]
    fSCA : (M, N, 5, nDays)  fractional snow-covered area [0-1]
    SD   : (M, N, 5, nDays)  snow depth [m]

    Ensemble dimension (axis 2): 1=mean, 2=std, 3=25th, 4=median, 5=75th
    """
    data_dir = Path(data_dir)

    # ── Discover available file types from first tile ────────────────────────
    test_tile = f"N{lat_tiles[0]}_0W{lon_tiles[0]}_0"
    swe_files = _find_tile_files(data_dir, test_tile, wy_str, "SWE_SCA_POST")
    sd_files  = _find_tile_files(data_dir, test_tile, wy_str, "SD_POST")

    has_swe = len(swe_files) > 0
    has_sd  = len(sd_files)  > 0

    if not has_swe and not has_sd:
        raise FileNotFoundError(
            f"No NetCDF files found for tile {test_tile} in {data_dir}\n"
            "Run getUCLA_SR_BRB.py first."
        )

    # ── Discover variable names ──────────────────────────────────────────────
    test_file = swe_files[0] if has_swe else sd_files[0]
    with nc.Dataset(test_file) as ds:
        var_names = list(ds.variables.keys())
        print(f"{'SWE/SCA' if has_swe else 'SD'} file: {test_file.name}")
        print(f"  Variables: {', '.join(var_names)}")
        lat_var  = _find_var(var_names, ["Latitude",  "lat",  "latitude"])
        lon_var  = _find_var(var_names, ["Longitude", "lon",  "longitude"])
        if has_swe:
            swe_var  = _find_var(var_names, ["SWE_Post",  "SWE",  "swe"])
            fsca_var = _find_var(var_names, ["SCA_Post",  "fSCA", "fsca", "SCA"])

        # Dimensions from test data
        primary_var = swe_var if has_swe else _find_var(var_names, ["SD_Post", "SD", "sd"])
        arr = ds.variables[primary_var][:]   # shape: (days, ens, lat, lon)
        n_days = arr.shape[0]
        n_ens  = arr.shape[1]

        tile_lat_arr = ds.variables[lat_var][:]
        tile_lon_arr = ds.variables[lon_var][:]
        n_lat_pix = len(tile_lat_arr)
        n_lon_pix = len(tile_lon_arr)

    print(f"Per-tile: {n_lat_pix} lat x {n_lon_pix} lon x {n_ens} ens x {n_days} days")
    if has_swe:
        print(f"SWE var: {swe_var},  SCA var: {fsca_var}")

    if has_sd:
        sd_test = sd_files[0]
        with nc.Dataset(sd_test) as ds_sd:
            sd_var_names = list(ds_sd.variables.keys())
            print(f"SD file: {sd_test.name}")
            print(f"  Variables: {', '.join(sd_var_names)}")
            sd_var      = _find_var(sd_var_names, ["SD_Post", "SD", "sd", "snow_depth"])
            sd_lat_var  = _find_var(sd_var_names, ["Latitude",  "lat",  "latitude"])
            sd_lon_var  = _find_var(sd_var_names, ["Longitude", "lon",  "longitude"])
        print(f"SD var: {sd_var}")

    # ── Collect all lat/lon from every tile to build the mosaic grid ─────────
    all_lats: list[float] = []
    all_lons: list[float] = []

    for lt in lat_tiles:
        for ln in lon_tiles:
            tile_str = f"N{lt}_0W{ln}_0"
            files = (_find_tile_files(data_dir, tile_str, wy_str, "SWE_SCA_POST")
                     if has_swe else
                     _find_tile_files(data_dir, tile_str, wy_str, "SD_POST"))
            if not files:
                continue
            with nc.Dataset(files[0]) as ds:
                all_lats.extend(ds.variables[lat_var][:].tolist())
                all_lons.extend(ds.variables[lon_var][:].tolist())

    # Lat descending (north→south), lon ascending (west→east)
    lat_vec = np.sort(np.unique(all_lats))[::-1]
    lon_vec = np.sort(np.unique(all_lons))

    total_lat = len(lat_vec)
    total_lon = len(lon_vec)
    print(f"Mosaic grid: {total_lat} lat x {total_lon} lon pixels")

    # ── Allocate output arrays ───────────────────────────────────────────────
    SWE_out  = np.full((total_lat, total_lon, n_ens, n_days), np.nan, dtype=np.float32)
    fSCA_out = np.full((total_lat, total_lon, n_ens, n_days), np.nan, dtype=np.float32)
    SD_out   = np.full((total_lat, total_lon, n_ens, n_days), np.nan, dtype=np.float32)

    tol = 1e-6

    def _coord_idx(tile_coords: np.ndarray, mosaic_coords: np.ndarray) -> np.ndarray:
        """Map tile coordinate values to their indices in the mosaic vector."""
        idx = np.empty(len(tile_coords), dtype=int)
        for i, c in enumerate(tile_coords):
            dist = np.abs(mosaic_coords - c)
            best = int(np.argmin(dist))
            if dist[best] > tol:
                raise ValueError(
                    f"Coordinate {c:.6f} not found in mosaic grid "
                    f"(nearest: {mosaic_coords[best]:.6f}, dist: {dist[best]:.6f})"
                )
            idx[i] = best
        return idx

    # ── Read and place each tile ─────────────────────────────────────────────
    for lt in lat_tiles:
        for ln in lon_tiles:
            tile_str = f"N{lt}_0W{ln}_0"

            # SWE and fSCA
            if has_swe:
                swe_fs = _find_tile_files(data_dir, tile_str, wy_str, "SWE_SCA_POST")
                if swe_fs:
                    fname = swe_fs[0]
                    print(f"  Reading SWE/SCA: {fname.name}")
                    with nc.Dataset(fname) as ds:
                        tile_lat = ds.variables[lat_var][:]
                        tile_lon = ds.variables[lon_var][:]
                        tile_swe  = ds.variables[swe_var][:]   # (days, ens, lat, lon)
                        tile_fsca = ds.variables[fsca_var][:]
                    # File is (day, ens, lon, lat); transpose to (lat, lon, ens, day)
                    tile_swe  = tile_swe.transpose(3, 2, 1, 0)
                    tile_fsca = tile_fsca.transpose(3, 2, 1, 0)
                    lat_idx = _coord_idx(tile_lat, lat_vec)
                    lon_idx = _coord_idx(tile_lon, lon_vec)
                    ix = np.ix_(lat_idx, lon_idx, np.arange(n_ens), np.arange(n_days))
                    SWE_out[ix]  = tile_swe
                    fSCA_out[ix] = tile_fsca
                else:
                    print(f"  WARNING: No SWE_SCA file for tile {tile_str}")

            # SD
            if has_sd:
                sd_fs = _find_tile_files(data_dir, tile_str, wy_str, "SD_POST")
                if sd_fs:
                    fname = sd_fs[0]
                    print(f"  Reading SD:      {fname.name}")
                    with nc.Dataset(fname) as ds:
                        tile_lat = ds.variables[sd_lat_var][:]
                        tile_lon = ds.variables[sd_lon_var][:]
                        tile_sd  = ds.variables[sd_var][:]   # (days, ens, lat, lon)
                    tile_sd = tile_sd.transpose(3, 2, 1, 0)
                    lat_idx = _coord_idx(tile_lat, lat_vec)
                    lon_idx = _coord_idx(tile_lon, lon_vec)
                    ix = np.ix_(lat_idx, lon_idx, np.arange(n_ens), np.arange(n_days))
                    SD_out[ix] = tile_sd
                else:
                    print(f"  WARNING: No SD file for tile {tile_str}")

    print(f"Mosaic complete: {total_lat} x {total_lon} pixels")
    return lat_vec, lon_vec, SWE_out, fSCA_out, SD_out


# ===========================================================================
# Shared map plotting helper
# ===========================================================================

def _plot_map(ax, plot_x, plot_y, data_masked, cmap, clim,
              shp_x=None, shp_y=None,
              snotel_x=None, snotel_y=None, snotel_names=None,
              xlabel="", ylabel="", title="", font_size=14):
    """imshow + basin outline + SNOTEL markers."""
    xmin, xmax = plot_x[0], plot_x[-1]
    ymin, ymax = plot_y[0], plot_y[-1]
    extent = [xmin, xmax, ymin, ymax]

    cmap_obj = cmap.copy() if hasattr(cmap, "copy") else plt.get_cmap(cmap)
    cmap_obj.set_bad(alpha=0)

    im = ax.imshow(
        data_masked,
        origin="lower",
        extent=extent,
        cmap=cmap_obj,
        vmin=clim[0],
        vmax=clim[1],
        interpolation="nearest",
        aspect="equal",
    )
    ax.autoscale(tight=True)

    if shp_x is not None:
        ax.plot(shp_x, shp_y, "k-", linewidth=2)

    if snotel_x is not None:
        ax.plot(snotel_x, snotel_y, "rp",
                markersize=12, markerfacecolor="r", linestyle="None")
        if snotel_names is not None:
            for xi, yi, name in zip(snotel_x, snotel_y, snotel_names):
                ax.text(xi, yi, "  " + name,
                        fontsize=8, fontweight="bold", color="r")

    ax.set_xlabel(xlabel, fontsize=font_size)
    ax.set_ylabel(ylabel, fontsize=font_size)
    ax.set_title(title, fontsize=font_size + 2)
    ax.tick_params(labelsize=font_size - 2)
    for spine in ax.spines.values():
        spine.set_linewidth(1.5)

    return im


def _mask_zeros(arr: np.ndarray) -> np.ma.MaskedArray:
    """Mask NaN and zero values (transparent rendering)."""
    return np.ma.masked_where(~np.isfinite(arr) | (arr == 0), arr)


def _safe_max(arr_m: np.ma.MaskedArray) -> float:
    c = arr_m.compressed()
    return float(c.max()) if len(c) > 0 else 1.0


def _make_inBRB(lon_grid, lat_grid, shp_lon, shp_lat) -> np.ndarray:
    valid = np.isfinite(shp_lon) & np.isfinite(shp_lat)
    verts = np.column_stack([shp_lon[valid], shp_lat[valid]])
    path  = MPath(verts)
    pts   = np.column_stack([lon_grid.ravel(), lat_grid.ravel()])
    return path.contains_points(pts).reshape(lon_grid.shape)


# ===========================================================================
# Main
# ===========================================================================

def main(
    wy_str: str    = "WY2020_21",
    wy_start_year: int = 2020,         # calendar year when the water year starts (Oct 1)
    lat_tiles: list[int] = None,
    lon_tiles: list[int] = None,
    target_date: int = 183,            # day of water year (1 = Oct 1); 183 = April 1
    ens_idx: int = 0,                  # 0-based: 0=mean, 1=std, 2=25th, 3=median, 4=75th
    use_utm: bool = True,
    data_dir: str = "/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR",
    out_dir: str | None = None,
    std_clim_max: float | None = None,   # upper color limit for uncertainty plot [cm]; None = auto
):
    if lat_tiles is None:
        lat_tiles = [43, 44]
    if lon_tiles is None:
        lon_tiles = [115, 116, 117]

    data_dir   = Path(data_dir)
    out_path   = Path(out_dir) if out_dir else data_dir
    out_path.mkdir(parents=True, exist_ok=True)
    script_dir = Path(__file__).parent.parent   # SnowFusion root
    shp_file   = script_dir / "BRB_outline.shp"
    snotel_shp = script_dir / "SNOTEL" / "IDDCO_2020_automated_sites.shp"

    # UTC transformer
    utm_fwd = Transformer.from_crs("EPSG:4326", "EPSG:26911", always_xy=False)
    utm_inv = Transformer.from_crs("EPSG:26911", "EPSG:4326", always_xy=False)

    # ── Read and mosaic tiles ────────────────────────────────────────────────
    print("Reading and mosaicing UCLA SR tiles ...")
    lat, lon, SWE, fSCA, SD = mosaic_ucla_sr(data_dir, wy_str, lat_tiles, lon_tiles)
    print(f"Grid size: {len(lat)} lat x {len(lon)} lon")

    # Ensure lat is ascending (south-to-north) so imshow origin="lower" is north-up
    if lat[0] > lat[-1]:
        lat  = lat[::-1]
        SWE  = SWE[::-1, ...]
        fSCA = fSCA[::-1, ...]
        SD   = SD[::-1, ...]
        print("Flipped latitude to ascending (south-to-north) for plotting.")

    # ── Load BRB shapefile ───────────────────────────────────────────────────
    print("Loading BRB shapefile ...")
    gdf = gpd.read_file(shp_file)
    shp_coords = np.array(gdf.geometry.iloc[0].exterior.coords)
    shp_utm_x = shp_coords[:, 0]
    shp_utm_y = shp_coords[:, 1]
    shp_lat_arr, shp_lon_arr = utm_inv.transform(shp_utm_x, shp_utm_y)
    valid = np.isfinite(shp_lat_arr) & np.isfinite(shp_lon_arr)
    print(
        f"BRB extent: lat [{shp_lat_arr[valid].min():.2f}, {shp_lat_arr[valid].max():.2f}], "
        f"lon [{shp_lon_arr[valid].min():.2f}, {shp_lon_arr[valid].max():.2f}]"
    )

    # ── BRB pixel mask ───────────────────────────────────────────────────────
    LON, LAT = np.meshgrid(lon, lat)
    in_brb = _make_inBRB(LON, LAT, shp_lon_arr, shp_lat_arr)
    print(
        f"Pixels inside BRB: {in_brb.sum()} of {in_brb.size} "
        f"({100*in_brb.sum()/in_brb.size:.1f}%)"
    )

    # ── SNOTEL sites ─────────────────────────────────────────────────────────
    snotel = getSNOTEL_BRB(
        snotel_shp,
        lat_lim=(lat.min(), lat.max()),
        lon_lim=(lon.min(), lon.max()),
    )
    print(f"Loaded {snotel['n_stations']} SNOTEL stations within plotted region")

    # ── Plotting coordinates ─────────────────────────────────────────────────
    if use_utm:
        e_grid, n_grid = utm_fwd.transform(LAT, LON)
        plot_x = e_grid[0, :] / 1000.0
        plot_y = n_grid[:, 0] / 1000.0
        plot_shp_x = shp_utm_x / 1000.0
        plot_shp_y = shp_utm_y / 1000.0
        snotel_e, snotel_n = utm_fwd.transform(snotel["lat"], snotel["lon"])
        plot_snotel_x = snotel_e / 1000.0
        plot_snotel_y = snotel_n / 1000.0
        xlabel = "Easting [km]"
        ylabel = "Northing [km]"
        print("Using UTM Zone 11N coordinates [km]")
    else:
        plot_x = lon
        plot_y = lat
        plot_shp_x = shp_lon_arr
        plot_shp_y = shp_lat_arr
        plot_snotel_x = snotel["lon"]
        plot_snotel_y = snotel["lat"]
        xlabel = "Longitude [deg]"
        ylabel = "Latitude [deg]"
        print("Using geographic coordinates [deg]")

    # ── Calendar date for target day ─────────────────────────────────────────
    wy_start = datetime(wy_start_year, 10, 1)
    target_dt = wy_start + timedelta(days=target_date - 1)
    date_str   = target_dt.strftime("%d-%b-%Y")
    wy_title   = wy_str.replace("_", " ")   # no TeX escape needed in matplotlib

    # ── Extract maps for target date (0-based indexing) ──────────────────────
    td = target_date - 1   # 0-based day index

    SWE_map  = SWE[:, :, ens_idx, td].copy()     # [m]
    fSCA_map = fSCA[:, :, ens_idx, td].copy()    # [0-1]
    SD_map   = SD[:, :, ens_idx, td].copy()      # [m]

    SWE_m  = _mask_zeros(SWE_map)
    fSCA_m = _mask_zeros(fSCA_map)
    SD_m   = _mask_zeros(SD_map)

    has_sd = bool(np.any(np.isfinite(SD_map)))
    if not has_sd:
        print("Note: SD_POST files not downloaded. Skipping snow depth plot.")

    SWE_cm  = SWE_m  * 100.0
    fSCA_pct = fSCA_m * 100.0
    SD_cm   = SD_m   * 100.0

    # Colormaps
    parula_cmap     = PARULA.copy(); parula_cmap.set_bad(alpha=0)
    white_par       = _white_parula_cmap()

    # Shared keyword blocks
    map_kw_full = dict(
        shp_x=plot_shp_x, shp_y=plot_shp_y,
        snotel_x=plot_snotel_x, snotel_y=plot_snotel_y,
        snotel_names=snotel["name"],
        xlabel=xlabel, ylabel=ylabel,
        font_size=14,
    )
    map_kw_panel = dict(
        shp_x=plot_shp_x, shp_y=plot_shp_y,
        snotel_x=plot_snotel_x, snotel_y=plot_snotel_y,
        snotel_names=None,
        xlabel=xlabel, ylabel=ylabel,
        font_size=12,
    )

    # =========================================================================
    # Figure 1: SWE map
    # =========================================================================
    fig1, ax1 = plt.subplots(figsize=(9, 7))
    fig1.patch.set_facecolor("white")
    im = _plot_map(ax1, plot_x, plot_y, SWE_cm,
                   parula_cmap, (0, _safe_max(SWE_cm)),
                   title=f"UCLA SR - SWE [cm] - {date_str}\nBoise River Basin, {wy_title}",
                   **map_kw_full)
    fig1.colorbar(im, ax=ax1, label="SWE [cm]")
    fig1.tight_layout()
    out1 = out_path / f"BRB_SWE_{wy_str}_day{target_date:03d}.png"
    fig1.savefig(out1, dpi=150, bbox_inches="tight")
    print(f"Saved {out1}")

    # =========================================================================
    # Figure 2: fSCA map
    # =========================================================================
    fig2, ax2 = plt.subplots(figsize=(9, 7))
    fig2.patch.set_facecolor("white")
    im = _plot_map(ax2, plot_x, plot_y, fSCA_pct,
                   white_par, (0, 100),
                   title=f"UCLA SR - fSCA [%] - {date_str}\nBoise River Basin, {wy_title}",
                   **map_kw_full)
    fig2.colorbar(im, ax=ax2, label="fSCA [%]")
    fig2.tight_layout()
    out2 = out_path / f"BRB_fSCA_{wy_str}_day{target_date:03d}.png"
    fig2.savefig(out2, dpi=150, bbox_inches="tight")
    print(f"Saved {out2}")

    # =========================================================================
    # Figure 3: Snow Depth map (if available)
    # =========================================================================
    if has_sd:
        fig3, ax3 = plt.subplots(figsize=(9, 7))
        fig3.patch.set_facecolor("white")
        im = _plot_map(ax3, plot_x, plot_y, SD_cm,
                       parula_cmap, (0, _safe_max(SD_cm)),
                       title=f"UCLA SR - Snow Depth [cm] - {date_str}\nBoise River Basin, {wy_title}",
                       **map_kw_full)
        fig3.colorbar(im, ax=ax3, label="Snow Depth [cm]")
        fig3.tight_layout()
        out3 = out_path / f"BRB_SD_{wy_str}_day{target_date:03d}.png"
        fig3.savefig(out3, dpi=150, bbox_inches="tight")
        print(f"Saved {out3}")
    else:
        print("  To download SD, update getUCLA_SR_BRB.py to include SD_POST files.")

    # =========================================================================
    # Figure 4: 3-panel summary
    # =========================================================================
    fig4, axes = plt.subplots(1, 3, figsize=(16, 5))
    fig4.patch.set_facecolor("white")

    im0 = _plot_map(axes[0], plot_x, plot_y, SWE_cm,
                    parula_cmap, (0, _safe_max(SWE_cm)),
                    title=f"SWE [cm]\n{date_str}", **map_kw_panel)
    fig4.colorbar(im0, ax=axes[0])

    im1 = _plot_map(axes[1], plot_x, plot_y, fSCA_pct,
                    white_par, (0, 100),
                    title=f"fSCA [%]\n{date_str}", **map_kw_panel)
    fig4.colorbar(im1, ax=axes[1])

    if has_sd:
        panel3_data  = SD_cm
        panel3_clim  = (0, _safe_max(SD_cm))
        panel3_title = f"Snow Depth [cm]\n{date_str}"
        panel3_cmap  = parula_cmap
    elif SWE.shape[2] >= 2:
        swe_std_panel = SWE[:, :, 1, td] * 100   # ensemble std [cm]
        swe_std_panel = _mask_zeros(swe_std_panel)
        panel3_data  = swe_std_panel
        panel3_clim  = (0, _safe_max(swe_std_panel))
        panel3_title = f"SWE Uncertainty [cm]\n{date_str}"
        panel3_cmap  = parula_cmap
    else:
        panel3_data  = np.ma.masked_all(SWE_cm.shape)
        panel3_clim  = (0, 1)
        panel3_title = "No data"
        panel3_cmap  = parula_cmap

    im2 = _plot_map(axes[2], plot_x, plot_y, panel3_data,
                    panel3_cmap, panel3_clim,
                    title=panel3_title, **map_kw_panel)
    fig4.colorbar(im2, ax=axes[2])

    fig4.suptitle(f"UCLA Snow Reanalysis - Boise River Basin - {wy_title}",
                  fontsize=16, fontweight="bold")
    fig4.tight_layout()
    out4 = out_path / f"BRB_summary_{wy_str}_day{target_date:03d}.png"
    fig4.savefig(out4, dpi=150, bbox_inches="tight")
    print(f"Saved {out4}")

    # =========================================================================
    # Figure 5: Time series of basin-mean SWE
    # =========================================================================
    n_days    = SWE.shape[3]
    mean_swe  = np.full(n_days, np.nan)
    std_swe   = np.full(n_days, np.nan)
    has_std   = SWE.shape[2] >= 2

    print("Computing basin-mean SWE time series ...")
    for d in range(n_days):
        swe_d = SWE[:, :, 0, d].copy()   # ensemble mean
        swe_d[~in_brb] = np.nan
        mean_swe[d] = np.nanmean(swe_d)
        if has_std:
            swe_s = SWE[:, :, 1, d].copy()
            swe_s[~in_brb] = np.nan
            std_swe[d] = np.nanmean(swe_s)

    dates = np.array([wy_start + timedelta(days=d) for d in range(n_days)])

    fig5, ax5 = plt.subplots(figsize=(10, 4))
    fig5.patch.set_facecolor("white")

    ax5.plot(dates, mean_swe * 100, "b-", linewidth=2, label="Basin Mean SWE")

    if has_std and np.any(np.isfinite(std_swe)):
        upper = (mean_swe + std_swe) * 100
        lower = (mean_swe - std_swe) * 100
        ax5.fill_between(dates, lower, upper, color="b", alpha=0.2, label=r"$\pm 1\sigma$")

    # Mark April 1 of the correct calendar year
    apr1_year = wy_start_year + 1
    apr1 = datetime(apr1_year, 4, 1)
    ax5.axvline(apr1, color="r", linestyle="--", linewidth=1.5)
    ax5.text(apr1, ax5.get_ylim()[1] * 0.98, "  Apr 1",
             fontsize=12, va="top", color="r")

    ax5.set_xlabel("Date", fontsize=14)
    ax5.set_ylabel("Basin Mean SWE [cm]", fontsize=14)
    ax5.set_title(
        f"Boise River Basin Mean SWE - {wy_title}\n"
        r"UCLA Snow Reanalysis (ensemble mean $\pm 1\sigma$)",
        fontsize=14,
    )
    ax5.tick_params(labelsize=12)
    ax5.grid(True, alpha=0.4)
    ax5.set_xlim(dates[0], dates[-1])
    ax5.legend(fontsize=12, loc="upper left")

    fig5.tight_layout()
    out5 = out_path / f"BRB_SWE_timeseries_{wy_str}.png"
    fig5.savefig(out5, dpi=150, bbox_inches="tight")
    print(f"Saved {out5}")

    # =========================================================================
    # Figure 6: SWE Uncertainty map (ensemble std)
    # =========================================================================
    if SWE.shape[2] >= 2:
        swe_std_map = SWE[:, :, 1, td] * 100   # cm
        swe_std_m   = _mask_zeros(swe_std_map)

        fig6, ax6 = plt.subplots(figsize=(9, 7))
        fig6.patch.set_facecolor("white")
        std_clim = (0, std_clim_max if std_clim_max is not None else _safe_max(swe_std_m))
        im = _plot_map(ax6, plot_x, plot_y, swe_std_m,
                       parula_cmap, std_clim,
                       title=(f"UCLA SR - SWE Uncertainty (1\u03c3) [cm] - {date_str}\n"
                              f"Boise River Basin, {wy_title}"),
                       **map_kw_full)
        fig6.colorbar(im, ax=ax6, label="SWE std [cm]")
        fig6.tight_layout()
        out6 = out_path / f"BRB_SWE_uncertainty_{wy_str}_day{target_date:03d}.png"
        fig6.savefig(out6, dpi=150, bbox_inches="tight")
        print(f"Saved {out6}")

    # =========================================================================
    # Summary statistics
    # =========================================================================
    print(f"\n=== Summary for {wy_str} (day {target_date} = {date_str}) ===")
    print(f"Basin mean SWE:  {mean_swe[td]*100:.1f} cm")
    swe_valid = SWE_cm.compressed()
    if len(swe_valid):
        print(f"Basin max SWE:   {swe_valid.max():.1f} cm")
    fsca_valid = fSCA_pct.compressed()
    if len(fsca_valid):
        print(f"Basin mean fSCA: {fsca_valid.mean():.1f} %")
    if has_sd:
        sd_valid = SD_cm.compressed()
        if len(sd_valid):
            print(f"Basin mean SD:   {sd_valid.mean():.1f} cm")
            print(f"Basin max SD:    {sd_valid.max():.1f} cm")
    if has_std and np.isfinite(std_swe[td]):
        print(f"Basin mean SWE uncertainty: {std_swe[td]*100:.1f} cm")

    print(f"\nFigures saved to: {out_path}")
    plt.show()
    print("Done!")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Plot UCLA Snow Reanalysis data over the Boise River Basin"
    )
    parser.add_argument("--wy-str",       default="WY2020_21",
                        help="Water year string, e.g. WY2020_21 (default)")
    parser.add_argument("--wy-start-year", type=int, default=2020,
                        help="Calendar year that the water year starts (Oct 1). Default 2020.")
    parser.add_argument("--lat-tiles",    type=int, nargs="+", default=[43, 44],
                        help="Tile lower-left latitudes (default: 43 44)")
    parser.add_argument("--lon-tiles",    type=int, nargs="+", default=[115, 116, 117],
                        help="Tile lower-left west longitudes (default: 115 116 117)")
    parser.add_argument("--date",         type=str, default=None,
                        help="Target date YYYY-MM-DD (default: April 1 of the water year)")
    parser.add_argument("--target-date",  type=int, default=None,
                        help="Day of water year (1=Oct 1; 183=Apr 1). Ignored if --date given.")
    parser.add_argument("--ens-idx",      type=int, default=0,
                        help="0-based ensemble index (0=mean, 1=std, ...). Default 0.")
    parser.add_argument("--no-utm",       action="store_true",
                        help="Use geographic coords instead of UTM")
    parser.add_argument("--data-dir",     default="/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR",
                        help="Directory with downloaded .nc files")
    parser.add_argument("--out-dir",      default=None,
                        help="Directory for output PNG files (default: same as data directory)")
    parser.add_argument("--std-clim",     type=float, default=None,
                        help="Upper color limit for SWE uncertainty plot [cm] (default: auto)")
    args = parser.parse_args()

    # Resolve target day-of-water-year
    if args.date is not None:
        parsed = datetime.strptime(args.date, "%Y-%m-%d")
        wy_start = datetime(args.wy_start_year, 10, 1)
        target_date = (parsed - wy_start).days + 1
    elif args.target_date is not None:
        target_date = args.target_date
    else:
        target_date = 183   # April 1 default

    main(
        wy_str=args.wy_str,
        wy_start_year=args.wy_start_year,
        lat_tiles=args.lat_tiles,
        lon_tiles=args.lon_tiles,
        target_date=target_date,
        ens_idx=args.ens_idx,
        use_utm=not args.no_utm,
        data_dir=args.data_dir,
        out_dir=args.out_dir,
        std_clim_max=args.std_clim,
    )
