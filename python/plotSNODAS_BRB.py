"""
plotSNODAS_BRB.py
Visualize SNODAS data over the Boise River Basin (BRB).

Reads a SNODAS_BRB_WY####.npz file (produced by the Python version of
getSNODAS_BRB), clips to the BRB shapefile, and generates 6 figures:

    1. SWE map for target date
    2. Snow Depth map for target date
    3. Daily Melt map for target date
    4. 3-panel summary (SWE, Depth, Melt)
    5. Time series of basin-mean SWE and Depth over the water year
    6. SWE vs Snow Depth scatter + bulk density map

Coordinate options
    useUTM=True  -> UTM Zone 11N [km] on both axes  (default)
    useUTM=False -> geographic [deg]

HP Marshall, Boise State University
SnowFusion Project
Created: April 2026
"""

from __future__ import annotations

import sys
from pathlib import Path
from datetime import datetime, timedelta

import numpy as np
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import matplotlib.cm as cm
import geopandas as gpd
from pyproj import Transformer
from shapely.geometry import Point
from matplotlib.path import Path as MPath

# ── local helper (lives next to this file) ─────────────────────────────────
sys.path.insert(0, str(Path(__file__).parent))
from getSNOTEL_BRB import getSNOTEL_BRB


# ===========================================================================
# Utility helpers
# ===========================================================================

def _parula_cmap() -> mcolors.LinearSegmentedColormap:
    """Return a close approximation of MATLAB's parula colormap."""
    # Key control points sampled from the original parula table
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


def _melt_cmap() -> mcolors.ListedColormap:
    """White for zero melt, warm autumn colors for positive melt."""
    autumn = matplotlib.colormaps.get_cmap("autumn")(np.linspace(0, 1, 255))[::-1]
    white = np.array([[1, 1, 1, 1]])
    colors = np.vstack([white, autumn])
    return mcolors.ListedColormap(colors)


def _mask_zeros(arr: np.ndarray) -> np.ma.MaskedArray:
    """Mask NaN and zero values so they display as transparent."""
    masked = np.ma.masked_where(~np.isfinite(arr) | (arr == 0), arr)
    return masked


def _make_inBRB(lon_grid: np.ndarray, lat_grid: np.ndarray,
                shp_lon: np.ndarray, shp_lat: np.ndarray) -> np.ndarray:
    """Return boolean mask True where (lon_grid, lat_grid) lies inside BRB polygon."""
    # Drop NaN boundary markers
    valid = np.isfinite(shp_lon) & np.isfinite(shp_lat)
    verts = np.column_stack([shp_lon[valid], shp_lat[valid]])
    path = MPath(verts)
    pts = np.column_stack([lon_grid.ravel(), lat_grid.ravel()])
    mask = path.contains_points(pts).reshape(lon_grid.shape)
    return mask


def _plot_map(ax, plot_x, plot_y, data_masked, cmap, clim,
              shp_x=None, shp_y=None,
              snotel_x=None, snotel_y=None, snotel_names=None,
              xlabel="", ylabel="", title="", font_size=14):
    """Generic helper: imshow + shapefile outline + SNOTEL markers."""
    xmin, xmax = plot_x[0], plot_x[-1]
    ymin, ymax = plot_y[0], plot_y[-1]
    extent = [xmin, xmax, ymin, ymax]

    cmap_obj = plt.get_cmap(cmap) if isinstance(cmap, str) else cmap
    cmap_obj = cmap_obj.copy()
    cmap_obj.set_bad(alpha=0)      # NaN / masked → fully transparent

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

    if shp_x is not None and shp_y is not None:
        ax.plot(shp_x, shp_y, "k-", linewidth=2)

    if snotel_x is not None and snotel_y is not None:
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


# ===========================================================================
# Main
# ===========================================================================

def main(
    wy: int = 2021,
    target_month: int = 4,
    target_day: int = 1,
    use_utm: bool = True,
    data_root: str = "/Users/hpmarshall/DATA_DRIVE/SnowFusion",
    out_dir: str | None = None,
):
    script_dir = Path(__file__).parent.parent   # SnowFusion root
    data_dir   = Path(data_root) / "SNODAS"
    out_path   = Path(out_dir) if out_dir else data_dir
    out_path.mkdir(parents=True, exist_ok=True)
    shp_file   = script_dir / "BRB_outline.shp"
    snotel_shp = script_dir / "SNOTEL" / "IDDCO_2020_automated_sites.shp"

    # UTM Zone 11N transformer (always forward = lat/lon → E/N)
    utm_fwd = Transformer.from_crs("EPSG:4326", "EPSG:26911", always_xy=False)
    utm_inv = Transformer.from_crs("EPSG:26911", "EPSG:4326", always_xy=False)

    # ── Load data ────────────────────────────────────────────────────────────
    npz_file = data_dir / f"SNODAS_BRB_WY{wy}.npz"
    if not npz_file.exists():
        raise FileNotFoundError(
            f"Data file not found: {npz_file}\nRun getSNODAS_BRB.py first."
        )

    print(f"Loading {npz_file} ...")
    data = np.load(npz_file, allow_pickle=True)

    lat = data["lat"].copy()
    lon = data["lon"].copy()
    print(f"Grid size: {len(lat)} lat x {len(lon)} lon")

    # ── Ensure lat is south-to-north (ascending) for imshow origin='lower' ──
    if lat[0] > lat[-1]:
        lat = lat[::-1]
        flip_vars = ["SWE", "Depth", "Precip", "SnowPrecip",
                     "Tsnow", "SublimationBS", "Melt", "Sublimation"]
        data_dict: dict[str, np.ndarray] = {}
        for v in flip_vars:
            if v in data:
                data_dict[v] = data[v][::-1, ...]   # flip along axis 0
            else:
                data_dict[v] = None
        print("Flipped latitude to ascending (south-to-north) for plotting.")
    else:
        data_dict = {v: data[v] if v in data else None
                     for v in ["SWE", "Depth", "Precip", "SnowPrecip",
                               "Tsnow", "SublimationBS", "Melt", "Sublimation"]}

    # Prefer the 'datestr' field (YYYY-MM-DD strings) written by getSNODAS_BRB.py.
    # Fall back to numeric conversion only if datestr is absent.
    if "datestr" in data.files:
        dates = np.array([datetime.strptime(str(s), "%Y-%m-%d") for s in data["datestr"]])
    else:
        raw_dates = data["dates"]
        # Python ordinals for modern dates are ~730000+; MATLAB datenums are ~366 higher.
        # Distinguish by checking whether the value converts to a plausible year.
        probe = datetime.fromordinal(int(raw_dates[0]))
        if probe.year < 1970:
            # Ordinal too small → treat as MATLAB datenum
            dates = np.array([
                datetime(1, 1, 1) + timedelta(days=float(d) - 367)
                for d in raw_dates
            ])
        else:
            dates = np.array([datetime.fromordinal(int(d)) for d in raw_dates])

    # ── Load BRB shapefile ───────────────────────────────────────────────────
    has_shapefile = shp_file.exists()
    if has_shapefile:
        print("Loading BRB shapefile ...")
        gdf = gpd.read_file(shp_file)
        # Shapefile is in NAD83 UTM Zone 11N (EPSG:26911)
        # Convert to geographic for inpolygon test
        shp_coords = np.array(gdf.geometry.iloc[0].exterior.coords)
        shp_utm_x = shp_coords[:, 0]   # easting  [m]
        shp_utm_y = shp_coords[:, 1]   # northing [m]
        # Convert UTM → lat/lon
        shp_lat, shp_lon = utm_inv.transform(shp_utm_x, shp_utm_y)
        valid = np.isfinite(shp_lat) & np.isfinite(shp_lon)
        print(
            f"BRB extent: lat [{shp_lat[valid].min():.2f}, {shp_lat[valid].max():.2f}], "
            f"lon [{shp_lon[valid].min():.2f}, {shp_lon[valid].max():.2f}]"
        )
    else:
        print("WARNING: BRB shapefile not found. Plotting without basin outline.")
        shp_lat = shp_lon = shp_utm_x = shp_utm_y = None

    # ── Build BRB pixel mask ─────────────────────────────────────────────────
    LON, LAT = np.meshgrid(lon, lat)      # shapes (n_lat, n_lon)
    if has_shapefile:
        in_brb = _make_inBRB(LON, LAT, shp_lon, shp_lat)
        print(
            f"Pixels inside BRB: {in_brb.sum()} of {in_brb.size} "
            f"({100*in_brb.sum()/in_brb.size:.1f}%)"
        )
    else:
        in_brb = np.ones(LON.shape, dtype=bool)

    # ── Load SNOTEL sites ─────────────────────────────────────────────────────
    snotel = getSNOTEL_BRB(
        snotel_shp,
        lat_lim=(lat.min(), lat.max()),
        lon_lim=(lon.min(), lon.max()),
    )
    print(f"Loaded {snotel['n_stations']} SNOTEL stations within plotted region")

    # ── Plotting coordinate setup ─────────────────────────────────────────────
    if use_utm:
        # Convert data grid to UTM [km]
        e_grid, n_grid = utm_fwd.transform(LAT, LON)   # (lat, lon) → (easting, northing)
        plot_x = e_grid[0, :] / 1000.0                 # 1-D easting  [km]
        plot_y = n_grid[:, 0] / 1000.0                 # 1-D northing [km]

        # Shapefile: native UTM [km]
        if has_shapefile:
            plot_shp_x = shp_utm_x / 1000.0
            plot_shp_y = shp_utm_y / 1000.0
        else:
            plot_shp_x = plot_shp_y = None

        # SNOTEL → UTM [km]
        snotel_e, snotel_n = utm_fwd.transform(
            snotel["lat"], snotel["lon"]
        )
        plot_snotel_x = snotel_e / 1000.0
        plot_snotel_y = snotel_n / 1000.0

        xlabel = "Easting [km]"
        ylabel = "Northing [km]"
        print("Using UTM Zone 11N coordinates [km]")
    else:
        plot_x = lon
        plot_y = lat
        plot_shp_x = shp_lon if has_shapefile else None
        plot_shp_y = shp_lat if has_shapefile else None
        plot_snotel_x = snotel["lon"]
        plot_snotel_y = snotel["lat"]
        xlabel = "Longitude [deg]"
        ylabel = "Latitude [deg]"
        print("Using geographic coordinates [deg]")

    # ── Find target date ─────────────────────────────────────────────────────
    target_dt = datetime(wy, target_month, target_day)
    day_diffs = np.array([(d - target_dt).days for d in dates])
    day_idx   = int(np.argmin(np.abs(day_diffs)))
    actual_date = dates[day_idx]
    date_str    = actual_date.strftime("%d-%b-%Y")
    print(f"Target date: {date_str} (day index {day_idx})")

    # ── Extract maps ─────────────────────────────────────────────────────────
    SWE_full   = data_dict["SWE"]
    Depth_full = data_dict["Depth"]
    Melt_full  = data_dict["Melt"]

    SWE_map   = SWE_full[:, :, day_idx].copy()     # [m]
    Depth_map = Depth_full[:, :, day_idx].copy()   # [m]
    Melt_map  = Melt_full[:, :, day_idx].copy()    # [m]

    # Mask zeros (transparent)
    SWE_map_m   = _mask_zeros(SWE_map)
    Depth_map_m = _mask_zeros(Depth_map)
    Melt_map_m  = _mask_zeros(Melt_map)

    # Units for display
    SWE_cm   = SWE_map_m   * 100.0   # cm
    Depth_cm = Depth_map_m * 100.0   # cm
    Melt_mm  = Melt_map_m  * 1000.0  # mm

    def safe_max(arr_m):
        c = arr_m.compressed()
        return float(c.max()) if len(c) > 0 else 1.0

    # ── Common map kwargs ─────────────────────────────────────────────────────
    map_kw = dict(
        shp_x=plot_shp_x, shp_y=plot_shp_y,
        snotel_x=plot_snotel_x, snotel_y=plot_snotel_y,
        snotel_names=snotel["name"],
        xlabel=xlabel, ylabel=ylabel,
    )

    # =========================================================================
    # Figure 1: SWE map
    # =========================================================================
    fig1, ax1 = plt.subplots(figsize=(9, 7))
    fig1.patch.set_facecolor("white")
    im = _plot_map(ax1, plot_x, plot_y, SWE_cm,
                   PARULA, (0, safe_max(SWE_cm)),
                   title=f"SNODAS - SWE [cm] - {date_str}\nBoise River Basin, WY{wy}",
                   **map_kw)
    fig1.colorbar(im, ax=ax1, label="SWE [cm]")
    fig1.tight_layout()
    out1 = out_path / f"BRB_SNODAS_SWE_WY{wy}_day{day_idx:03d}.png"
    fig1.savefig(out1, dpi=150, bbox_inches="tight")
    print(f"Saved {out1}")

    # =========================================================================
    # Figure 2: Snow Depth map
    # =========================================================================
    fig2, ax2 = plt.subplots(figsize=(9, 7))
    fig2.patch.set_facecolor("white")
    im = _plot_map(ax2, plot_x, plot_y, Depth_cm,
                   PARULA, (0, safe_max(Depth_cm)),
                   title=f"SNODAS - Snow Depth [cm] - {date_str}\nBoise River Basin, WY{wy}",
                   **map_kw)
    fig2.colorbar(im, ax=ax2, label="Snow Depth [cm]")
    fig2.tight_layout()
    out2 = out_path / f"BRB_SNODAS_Depth_WY{wy}_day{day_idx:03d}.png"
    fig2.savefig(out2, dpi=150, bbox_inches="tight")
    print(f"Saved {out2}")

    # =========================================================================
    # Figure 3: Daily Melt map
    # =========================================================================
    melt_cmap = _melt_cmap()
    fig3, ax3 = plt.subplots(figsize=(9, 7))
    fig3.patch.set_facecolor("white")
    im = _plot_map(ax3, plot_x, plot_y, Melt_mm,
                   melt_cmap, (0, safe_max(Melt_mm)),
                   title=f"SNODAS - Daily Melt [mm] - {date_str}\nBoise River Basin, WY{wy}",
                   **map_kw)
    fig3.colorbar(im, ax=ax3, label="Melt [mm]")
    fig3.tight_layout()
    out3 = out_path / f"BRB_SNODAS_Melt_WY{wy}_day{day_idx:03d}.png"
    fig3.savefig(out3, dpi=150, bbox_inches="tight")
    print(f"Saved {out3}")

    # =========================================================================
    # Figure 4: 3-panel summary
    # =========================================================================
    fig4, axes = plt.subplots(1, 3, figsize=(16, 5))
    fig4.patch.set_facecolor("white")

    panel_kw = dict(
        shp_x=plot_shp_x, shp_y=plot_shp_y,
        snotel_x=plot_snotel_x, snotel_y=plot_snotel_y,
        snotel_names=None,           # omit labels in summary panel
        xlabel=xlabel, ylabel=ylabel,
        font_size=12,
    )

    im0 = _plot_map(axes[0], plot_x, plot_y, SWE_cm,
                    PARULA, (0, safe_max(SWE_cm)),
                    title=f"SWE [cm]\n{date_str}", **panel_kw)
    fig4.colorbar(im0, ax=axes[0])

    im1 = _plot_map(axes[1], plot_x, plot_y, Depth_cm,
                    PARULA, (0, safe_max(Depth_cm)),
                    title=f"Snow Depth [cm]\n{date_str}", **panel_kw)
    fig4.colorbar(im1, ax=axes[1])

    im2 = _plot_map(axes[2], plot_x, plot_y, Melt_mm,
                    melt_cmap, (0, safe_max(Melt_mm)),
                    title=f"Daily Melt [mm]\n{date_str}", **panel_kw)
    fig4.colorbar(im2, ax=axes[2])

    fig4.suptitle(f"SNODAS - Boise River Basin - WY{wy}",
                  fontsize=16, fontweight="bold")
    fig4.tight_layout()
    out4 = out_path / f"BRB_SNODAS_summary_WY{wy}_day{day_idx:03d}.png"
    fig4.savefig(out4, dpi=150, bbox_inches="tight")
    print(f"Saved {out4}")

    # =========================================================================
    # Figure 5: Time series of basin-mean SWE & Depth
    # =========================================================================
    n_days = len(dates)
    mean_swe   = np.full(n_days, np.nan)
    mean_depth = np.full(n_days, np.nan)
    mean_melt  = np.full(n_days, np.nan)

    print("Computing basin-mean time series ...")
    for d in range(n_days):
        swe_d = SWE_full[:, :, d].copy()
        swe_d[~in_brb] = np.nan
        mean_swe[d] = np.nanmean(swe_d)

        dep_d = Depth_full[:, :, d].copy()
        dep_d[~in_brb] = np.nan
        mean_depth[d] = np.nanmean(dep_d)

        melt_d = Melt_full[:, :, d].copy()
        melt_d[~in_brb] = np.nan
        mean_melt[d] = np.nanmean(melt_d) if np.any(np.isfinite(melt_d)) else 0.0

    fig5, ax5 = plt.subplots(figsize=(10, 4))
    fig5.patch.set_facecolor("white")

    color_swe   = "steelblue"
    color_depth = "firebrick"
    ax5_r = ax5.twinx()

    ax5.plot(dates, mean_swe * 100, color=color_swe, linewidth=2, label="SWE")
    ax5.set_ylabel("Basin Mean SWE [cm]", color=color_swe, fontsize=14)
    ax5.tick_params(axis="y", colors=color_swe)

    ax5_r.plot(dates, mean_depth * 100, color=color_depth, linewidth=1.5, label="Depth")
    ax5_r.set_ylabel("Basin Mean Depth [cm]", color=color_depth, fontsize=14)
    ax5_r.tick_params(axis="y", colors=color_depth)

    # Mark April 1
    apr1 = datetime(wy, 4, 1)
    ax5.axvline(apr1, color="k", linestyle="--", linewidth=1.5)
    ax5.text(apr1, ax5.get_ylim()[1], "  Apr 1", fontsize=12, va="top")

    ax5.set_xlabel("Date", fontsize=14)
    ax5.set_title(f"Boise River Basin - SNODAS SWE & Depth - WY{wy}", fontsize=14)
    ax5.tick_params(labelsize=12)
    ax5.grid(True, alpha=0.4)
    ax5.set_xlim(dates[0], dates[-1])

    # Combined legend
    lines_l, labels_l = ax5.get_legend_handles_labels()
    lines_r, labels_r = ax5_r.get_legend_handles_labels()
    ax5.legend(lines_l + lines_r, labels_l + labels_r, loc="upper left", fontsize=12)

    fig5.tight_layout()
    out5 = out_path / f"BRB_SNODAS_SWE_timeseries_WY{wy}.png"
    fig5.savefig(out5, dpi=150, bbox_inches="tight")
    print(f"Saved {out5}")

    # =========================================================================
    # Figure 6: SWE vs Snow Depth scatter + bulk density map
    # =========================================================================
    fig6, (ax6a, ax6b) = plt.subplots(2, 1, figsize=(10, 8))
    fig6.patch.set_facecolor("white")

    # Pixels valid for scatter: inside BRB, both positive
    valid_px = (
        in_brb
        & np.isfinite(SWE_map) & (SWE_map > 0)
        & np.isfinite(Depth_map) & (Depth_map > 0)
    )
    swe_px  = SWE_map[valid_px]   * 100   # cm
    dep_px  = Depth_map[valid_px] * 100   # cm

    if len(swe_px) > 0:
        ax6a.scatter(dep_px, swe_px, s=3, c="steelblue",
                     alpha=0.10, linewidths=0, rasterized=True)
        max_val = max(dep_px.max(), swe_px.max())
        xline = np.array([0, max_val])
        ax6a.plot(xline, xline * 0.30, "r--", linewidth=1.5, label=r"$\rho$ = 0.30")
        ax6a.plot(xline, xline * 0.50, "g--", linewidth=1.5, label=r"$\rho$ = 0.50")

        mean_density = np.nanmean(swe_px / dep_px)
        ax6a.text(0.95, 0.05,
                  rf"Mean $\rho_{{bulk}}$ = {mean_density:.2f}",
                  transform=ax6a.transAxes,
                  ha="right", va="bottom",
                  fontsize=13, fontweight="bold",
                  bbox=dict(facecolor="white", edgecolor="none"))
    else:
        mean_density = np.nan

    ax6a.set_xlabel("Snow Depth [cm]", fontsize=13)
    ax6a.set_ylabel("SWE [cm]", fontsize=13)
    ax6a.set_title(f"SWE vs Snow Depth - {date_str}", fontsize=14)
    ax6a.legend(loc="upper left", fontsize=12)
    ax6a.tick_params(labelsize=12)
    ax6a.grid(True, alpha=0.4)

    # Bulk density map
    density_map = np.full(SWE_map.shape, np.nan)
    valid_den = np.isfinite(SWE_map) & (SWE_map > 0) & np.isfinite(Depth_map) & (Depth_map > 0)
    density_map[valid_den] = SWE_map[valid_den] / Depth_map[valid_den]
    density_masked = np.ma.masked_invalid(density_map)

    # Build parula + white-first cmap for density
    den_cmap = PARULA.copy()
    den_cmap.set_bad(alpha=0)

    im6 = _plot_map(ax6b, plot_x, plot_y, density_masked,
                    den_cmap, (0, 0.6),
                    title=(f"SNODAS - Bulk Snow Density [SWE/Depth] - {date_str}\n"
                           f"Boise River Basin, WY{wy}"),
                    **{**map_kw, "font_size": 12})
    fig6.colorbar(im6, ax=ax6b, label="SWE / Depth")

    fig6.tight_layout()
    out6 = out_path / f"BRB_SNODAS_density_WY{wy}_day{day_idx:03d}.png"
    fig6.savefig(out6, dpi=150, bbox_inches="tight")
    print(f"Saved {out6}")

    # =========================================================================
    # Summary statistics
    # =========================================================================
    print(f"\n=== Summary for WY{wy} (day {day_idx} = {date_str}) ===")
    print(f"Basin mean SWE:    {mean_swe[day_idx]*100:.1f} cm")
    swe_vals_valid = SWE_cm.compressed()
    print(f"Basin max SWE:     {swe_vals_valid.max():.1f} cm" if len(swe_vals_valid) else "Basin max SWE:     --")
    print(f"Basin mean Depth:  {mean_depth[day_idx]*100:.1f} cm")
    dep_vals_valid = Depth_cm.compressed()
    print(f"Basin max Depth:   {dep_vals_valid.max():.1f} cm" if len(dep_vals_valid) else "Basin max Depth:   --")
    print(f"Basin mean Melt:   {mean_melt[day_idx]*1000:.2f} mm")
    if not np.isnan(mean_density):
        print(f"Mean bulk density: {mean_density:.2f}")

    peak_idx = int(np.nanargmax(mean_swe))
    print(
        f"\nPeak basin-mean SWE: {mean_swe[peak_idx]*100:.1f} cm "
        f"on {dates[peak_idx].strftime('%d-%b-%Y')}"
    )
    print(f"\nFigures saved to: {out_path}")
    plt.show()
    print("Done!")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Plot SNODAS data over the Boise River Basin"
    )
    parser.add_argument("--wy",      type=int,  default=2021, help="Water year (default 2021)")
    parser.add_argument("--date",    type=str,  default=None,
                        help="Target date YYYY-MM-DD (default: April 1 of the water year)")
    parser.add_argument("--month",   type=int,  default=4,    help="Target month (default 4, ignored if --date given)")
    parser.add_argument("--day",     type=int,  default=1,    help="Target day of month (default 1, ignored if --date given)")
    parser.add_argument("--no-utm",  action="store_true",     help="Use geographic coords instead of UTM")
    parser.add_argument("--data-root", default="/Users/hpmarshall/DATA_DRIVE/SnowFusion",
                        help="Root data directory")
    parser.add_argument("--out-dir", default=None,
                        help="Directory for output PNG files (default: same as data directory)")
    args = parser.parse_args()

    if args.date is not None:
        parsed = datetime.strptime(args.date, "%Y-%m-%d")
        target_month = parsed.month
        target_day   = parsed.day
    else:
        target_month = args.month
        target_day   = args.day

    main(
        wy=args.wy,
        target_month=target_month,
        target_day=target_day,
        use_utm=not args.no_utm,
        data_root=args.data_root,
        out_dir=args.out_dir,
    )
