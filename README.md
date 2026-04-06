# SnowFusion

MATLAB and Python tools for downloading, processing, and visualizing gridded snow products over the Boise River Basin (BRB). Combines two complementary data sources: NOAA's Snow Data Assimilation System (SNODAS) and the UCLA Western US Snow Reanalysis (WUS_UCLA_SR).

**Author:** HP Marshall, Boise State University
**Created:** April 2026

Both MATLAB and Python implementations are provided with equivalent functionality. Jump to the relevant quick-start section:

- [MATLAB Quick Start](#quick-start) — uses `.mat` files, Mapping Toolbox, `VideoWriter`
- [Python Quick Start](#python-quick-start) — uses `.npz`/`.pkl` files, `matplotlib`, `imageio`; supports `--date` and `--out-dir` command-line options

---

## Data Sources

**SNODAS (G02158)** -- NOAA Snow Data Assimilation System
- URL: https://nsidc.org/data/g02158/versions/1
- Resolution: ~1 km (30 arc-second), daily
- Coverage: CONUS, October 2003 to present
- Variables: SWE, snow depth, precipitation, snowfall, snow temperature, melt, sublimation (8 total)
- Access: HTTPS from `noaadata.apps.nsidc.org` (no authentication required)

**WUS UCLA Snow Reanalysis (WUS_UCLA_SR v01)** -- UCLA/JPL
- URL: https://nsidc.org/data/wus_ucla_sr/versions/1
- Resolution: ~500 m (16 arc-second), daily
- Coverage: Western US, WY1985--WY2021
- Variables: SWE, fractional snow-covered area (fSCA), snow depth -- each with ensemble statistics (mean, std, median, 25th/75th percentiles)
- Access: NASA Earthdata Cloud (requires Earthdata login)

---

## Repository Structure

```
SnowFusion/
  BRB_outline.shp (.dbf, .prj, .sbn, .sbx, .shx)   -- Boise River Basin shapefile (UTM Zone 11N)
  README.md                                           -- This file

  -- SNODAS Download & Processing --
  getSNODAS_BRB.m       Script: download SNODAS via HTTPS for a full water year
  getSNODAS_WY.m        Function: download SNODAS via FTP (alternate method)
  loadSNODAS_var.m      Function: load a single variable from cached .mat files

  -- UCLA Snow Reanalysis Download & Processing --
  getUCLA_SR_BRB.m      Script: download UCLA SR NetCDF tiles from Earthdata
  mosaicUCLA_SR.m       Function: read and mosaic 1-deg x 1-deg NetCDF tiles
  getUCLA_SWE.m         Function: load UCLA tiles, extract ensemble stats for a region

  -- Ground Truth --
  getSNOTEL_BRB.m       Function: returns SNOTEL station locations within a region

  -- Visualization --
  plotSNODAS_BRB.m      Script: 6 publication-quality figures from SNODAS data
  plotUCLA_SR_BRB.m     Script: 6 publication-quality figures from UCLA SR data
  plotSnowVar.m         Function: generic single-date map for any snow variable
  makeSnowMovie.m       Function: generic MP4 movie for any snow variable
  movieSNODAS_BRB.m     Script: quick SNODAS animation with variable selection
  snowViz.m             Script: interactive menu-driven visualization driver
  compareSWE_movie.m    Script: side-by-side SNODAS vs UCLA SWE movie

  -- Utilities --
  earthdata_credentials.m   Script: local NASA Earthdata credentials (DO NOT COMMIT)
  diagnoseTiles.m            Script: diagnostic checks on UCLA tile coordinate ordering

  -- Python Implementation --
  python/               Python equivalents of all root .m files (see below)

  -- Subdirectories (legacy/original code) --
  SNODAS/               Original SNODAS scripts and earlier versions
  UCLA_SR/              Original UCLA SR scripts
  .gitignore            Excludes data files and credential files from git

External data directory (not in git repo):
  /Users/hpmarshall/DATA_DRIVE/SnowFusion/
    SNODAS/             Downloaded SNODAS .mat/.pkl files and figures
    UCLA_SR/            Downloaded UCLA .nc files and figures
    Movies/             Output MP4 movies
    temp_download/      Temporary extraction directory (auto-cleaned)
```

---

## Quick Start

### 1. Download SNODAS Data

Edit `getSNODAS_BRB.m` to set the water year, then run:

```matlab
>> getSNODAS_BRB
```

This downloads all 8 SNODAS variables for the full water year, converts units, and saves to `/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS/SNODAS_BRB_WY2021.mat`. Individual daily .mat files are cached so interrupted downloads can resume. All data files are stored on the external data drive to keep the git repo lightweight.

**Alternative (function form):**

```matlab
BB = [-116.2 -114.6 43.2 44.4];  % Boise River Basin bounding box
Snodas = getSNODAS_WY(2020, BB);
```

`getSNODAS_WY` uses FTP access (`sidads.colorado.edu`) and returns the data structure directly.

### 2. Download UCLA Snow Reanalysis Data

Run `getUCLA_SR_BRB.m`. The script will use credentials from `earthdata_credentials.m` (which you must create locally — see [NASA Earthdata Credentials](#nasa-earthdata-credentials)):

```matlab
>> getUCLA_SR_BRB
```

This downloads the 1-deg x 1-deg NetCDF tiles covering the BRB. If automated download fails, the script prints manual download instructions via NSIDC's Data Access Tool.

### 3. Visualize SNODAS Data

After downloading, run:

**MATLAB** (date is set at the top of the script):
```matlab
>> plotSNODAS_BRB
```

**Python** (date and output directory are command-line options):
```bash
# Default: April 1 of the water year
python python/plotSNODAS_BRB.py

# Specific date
python python/plotSNODAS_BRB.py --date 2021-03-15

# Specific date, save figures to a custom directory
python python/plotSNODAS_BRB.py --date 2021-04-01 --out-dir ~/Desktop/snodas_figs
```

Both versions generate 6 figures:

1. SWE map (April 1 by default) in cm
2. Snow depth map in cm
3. Daily melt map in mm
4. 3-panel summary (SWE, depth, melt)
5. Time series of basin-mean SWE and depth over the water year
6. SWE vs. snow depth scatter with bulk density analysis

See [Python Visualization Options](#python-visualization-options) for the full list of command-line arguments.

### 4. Visualize UCLA Snow Reanalysis Data

**MATLAB** (date is set at the top of the script):
```matlab
>> plotUCLA_SR_BRB
```

**Python** (date and output directory are command-line options):
```bash
# Default: April 1 of the water year
python python/plotUCLA_SR_BRB.py

# Specific date
python python/plotUCLA_SR_BRB.py --date 2021-03-15

# Specific date, save figures to a custom directory
python python/plotUCLA_SR_BRB.py --date 2021-04-01 --out-dir ~/Desktop/ucla_figs
```

Both versions generate 6 figures:

1. SWE map (ensemble mean, April 1) in cm
2. Fractional snow-covered area map in percent
3. Snow depth map in cm
4. 3-panel summary (SWE, fSCA, depth)
5. Time series of basin-mean SWE with ensemble uncertainty envelope
6. SWE uncertainty map (ensemble standard deviation)

See [Python Visualization Options](#python-visualization-options) for the full list of command-line arguments.

### 5. Side-by-Side Comparison Movie

```matlab
>> compareSWE_movie
```

Creates a single MP4 with two panels: SNODAS SWE (left) and UCLA SR SWE ensemble mean (right), sharing the same color scale and date, with BRB outline and SNOTEL sites overlaid on both panels. Saved to `DATA_DRIVE/SnowFusion/Movies/`.

### 6. Interactive Visualization

```matlab
>> snowViz
```

Presents a menu-driven interface to select data source (SNODAS or UCLA), variable, and visualization mode (single figure or water year movie).

---

## Function Reference

### Data Download and Loading

#### `getSNODAS_WY(WY, BB, outDir)`

Download SNODAS data for a complete water year via FTP.

```matlab
% Download WY2020 for Boise River Basin
BB = [-116.2 -114.6 43.2 44.4];
Snodas = getSNODAS_WY(2020, BB);

% Download WY2019 for a custom region, save to specific directory
BB_custom = [-117.0 -115.0 42.5 44.0];
Snodas = getSNODAS_WY(2019, BB_custom, './my_data');
```

**Inputs:**
- `WY` -- Water year (e.g., 2020 = Oct 2019 through Sep 2020)
- `BB` -- Bounding box `[lonmin lonmax latmin latmax]` (default: BRB)
- `outDir` -- Output directory (default: current directory)

**Output:** Structure with fields `.WY`, `.lat`, `.lon`, `.dates`, `.datestr`, `.SWE`, `.Depth`, `.Precip`, `.SnowPrecip`, `.Tsnow`, `.Melt`, `.Sublimation`, `.SublimationBS`

All variables are 3D arrays `[nLat x nLon x nDays]` with physical units (meters, Kelvin, kg/m^2).

---

#### `getUCLA_SWE(WY, BB, dataDir)`

Load UCLA Snow Reanalysis from locally downloaded NetCDF tiles.

```matlab
% Load WY2020 for BRB from downloaded tiles
UCLA = getUCLA_SWE(2020, [-116.2 -114.6 43.2 44.4], './UCLA_data');

% Access ensemble mean SWE for April 1
apr1_idx = 183;  % day of water year
swe_map = UCLA.SWE_mean(:,:,apr1_idx);
```

**Inputs:**
- `WY` -- Water year (1985--2021)
- `BB` -- Bounding box `[lonmin lonmax latmin latmax]`
- `dataDir` -- Directory containing downloaded `.nc` files

**Output:** Structure with fields `.SWE_mean`, `.SWE_std`, `.SWE_median`, `.SWE_p25`, `.SWE_p75`, `.fSCA_mean`, `.SD_mean`, `.SD_std`, `.SD_median`, plus `.lat`, `.lon`, `.dates`, `.WY`

---

#### `loadSNODAS_var(matFile, varName)`

Load a single variable from a cached SNODAS .mat file.

```matlab
[swe, lat, lon] = loadSNODAS_var('/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS/SNODAS_BRB_WY2021.mat', 'SWE');
[depth, lat, lon] = loadSNODAS_var('/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS/SNODAS_BRB_WY2021.mat', 'Depth');
```

**Inputs:**
- `matFile` -- Path to .mat file from `getSNODAS_BRB` or individual day cache
- `varName` -- One of: `'Precip'`, `'SnowPrecip'`, `'SWE'`, `'Depth'`, `'Tsnow'`, `'SublimationBS'`, `'Melt'`, `'Sublimation'`

**Outputs:** `data` [nLat x nLon x nDays], `lat`, `lon`

---

#### `mosaicUCLA_SR(dataDir, wyStr, latTiles, lonTiles)`

Read and mosaic multiple UCLA Snow Reanalysis NetCDF tiles into a continuous grid.

```matlab
[lat, lon, SWE, fSCA, SD] = mosaicUCLA_SR('./data', 'WY2020_21', [43 44], [115 116 117]);

% SWE dimensions: [nLat x nLon x 5 x nDays]
% Ensemble stats: dim 3 -> 1=mean, 2=std, 3=25th pctl, 4=median, 5=75th pctl
apr1_mean_swe = SWE(:,:,1,183);  % ensemble mean SWE on April 1
```

**Inputs:**
- `dataDir` -- Directory containing `.nc` files
- `wyStr` -- Water year string, e.g., `'WY2020_21'`
- `latTiles` -- Vector of tile lower-left latitudes, e.g., `[43 44]`
- `lonTiles` -- Vector of tile lower-left west longitudes, e.g., `[115 116 117]`

**Outputs:** `lat` vector, `lon` vector, plus 4D arrays `SWE`, `fSCA`, `SD` each `[nLat x nLon x 5 x nDays]`

---

### Ground Truth

#### `getSNOTEL_BRB(shpPath, latLim, lonLim)`

Return SNOTEL station locations within a specified region, read from a shapefile.

```matlab
snotel = getSNOTEL_BRB('SNOTEL/IDDCO_2020_automated_sites.shp', [43 45], [-117 -114]);
fprintf('%d stations found\n', snotel.nStations);

% Plot stations on a map
plot(snotel.lon, snotel.lat, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
```

**Inputs:**
- `shpPath` -- Path to SNOTEL shapefile (`SNOTEL/IDDCO_2020_automated_sites.shp`)
- `latLim` -- Latitude limits `[latMin latMax]`
- `lonLim` -- Longitude limits `[lonMin lonMax]`

**Output:** Structure with fields `.name`, `.siteNum`, `.lat`, `.lon`, `.elev_ft`, `.nStations`

---

### Visualization

All visualization scripts and functions overlay the BRB outline (black line) and SNOTEL station locations (filled red pentagrams) on every map. The generic functions `plotSnowVar` and `makeSnowMovie` accept a `'snotel'` name-value parameter (`true` by default) to toggle the SNOTEL overlay.

#### `plotSnowVar(dataStruct, varName, targetDate, ...)`

Generic single-date map for any snow variable from either SNODAS or UCLA data.

```matlab
% Plot SNODAS SWE on April 1
load('/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS/SNODAS_BRB_WY2021.mat');
plotSnowVar(Snodas, 'SWE', '2021-04-01');

% Plot with shapefile overlay and custom color limits
plotSnowVar(Snodas, 'Depth', '2021-04-01', ...
    'shapefile', 'BRB_outline.shp', ...
    'clim', [0 2.0], ...
    'saveFig', 'depth_apr1.png');

% Plot UCLA SWE mean
load('/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR/UCLA_SWE_WY2020.mat');
plotSnowVar(UCLA, 'SWE_mean', '2020-04-01', ...
    'shapefile', 'BRB_outline.shp', ...
    'cmap', 'parula');
```

**Name-Value Options:** `'clim'`, `'cmap'`, `'title'`, `'shapefile'`, `'figHandle'`, `'saveFig'`, `'units'`, `'latlim'`, `'lonlim'`, `'snotel'` (default `true`)

**Supported SNODAS variables:** `SWE`, `Depth`, `Precip`, `SnowPrecip`, `Tsnow`, `Melt`, `Sublimation`, `SublimationBS`

**Supported UCLA variables:** `SWE_mean`, `SWE_median`, `SWE_std`, `SWE_p25`, `SWE_p75`, `fSCA_mean`, `SD_mean`, `SD_median`, `SD_std`

---

#### `makeSnowMovie(dataStruct, varName, movieFile, ...)`

Create an MP4 animation of any snow variable over the water year.

```matlab
% SNODAS SWE movie
load('/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS/SNODAS_BRB_WY2021.mat');
makeSnowMovie(Snodas, 'SWE', 'SNODAS_SWE_WY2021.mp4', ...
    'shapefile', 'BRB_outline.shp', ...
    'fps', 12);

% UCLA SWE movie, every other day, custom color range
load('/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR/UCLA_SWE_WY2020.mat');
makeSnowMovie(UCLA, 'SWE_mean', 'UCLA_SWE_WY2020.mp4', ...
    'fps', 15, ...
    'skipDays', 2, ...
    'clim', [0 0.8]);

% Melt movie for spring only (March through June)
makeSnowMovie(Snodas, 'Melt', 'Melt_spring.mp4', ...
    'dateRange', [datenum(2021,3,1) datenum(2021,6,30)], ...
    'fps', 8, ...
    'quality', 95);
```

**Name-Value Options:** `'clim'`, `'cmap'`, `'fps'`, `'quality'`, `'shapefile'`, `'dateRange'`, `'titlePrefix'`, `'skipDays'`, `'latlim'`, `'lonlim'`, `'figSize'`, `'snotel'` (default `true`)

---

#### `compareSWE_movie`

Script that produces a side-by-side MP4 comparing SNODAS SWE (left) and UCLA SR ensemble mean SWE (right) for a full water year. Both panels share the same spatial extent, color scale (0–1.5 m), date label, BRB outline, and SNOTEL site overlays. Output is saved to `DATA_DRIVE/SnowFusion/Movies/SWE_comparison_SNODAS_UCLA_WY<YEAR>.mp4`.

Configuration is set at the top of the script:

```matlab
WY       = 2021;
FPS      = 10;
SKIP_DAYS = 2;     % render every other day
LATLIM   = [43.0 45.0];
LONLIM   = [-117.0 -114.0];
CLIM_SWE = [0 1.5];  % SWE color limits [m]
```

---

## NASA Earthdata Credentials

UCLA SR data requires a free NASA Earthdata account (register at https://urs.earthdata.nasa.gov).

**MATLAB:** Create a local file `earthdata_credentials.m` in the repo root (it is excluded from git by `.gitignore`):

```matlab
% earthdata_credentials.m  -- DO NOT COMMIT
earthdata_user = 'YOUR_USERNAME';
earthdata_pass = 'YOUR_PASSWORD';
```

**Python:** Run `python/earthdata_credentials.py` once to securely store credentials in `~/.netrc`:

```
python python/earthdata_credentials.py
```

Credentials are stored in `~/.netrc` with permissions `600` and are read automatically by subsequent download scripts.

---

## Python Implementation

The `python/` directory contains Python equivalents of all root-level MATLAB scripts and functions. The Python versions use the same algorithms, produce equivalent outputs, and read/write compatible data formats (`.pkl`/`.npz` instead of `.mat`).

### Python File Reference

| Python file | Equivalent MATLAB file | Description |
|---|---|---|
| `getSNODAS_BRB.py` | `getSNODAS_BRB.m` | Download SNODAS via HTTPS for a full water year |
| `getSNODAS_WY.py` | `getSNODAS_WY.m` | Download SNODAS via FTP (alternate method) |
| `loadSNODAS_var.py` | `loadSNODAS_var.m` | Load a single variable from cached files |
| `getUCLA_SR_BRB.py` | `getUCLA_SR_BRB.m` | Download UCLA SR NetCDF tiles from Earthdata |
| `mosaicUCLA_SR.py` | `mosaicUCLA_SR.m` | Read and mosaic 1-deg UCLA tiles |
| `getUCLA_SWE.py` | `getUCLA_SWE.m` | Load UCLA tiles with ensemble statistics |
| `getSNOTEL_BRB.py` | `getSNOTEL_BRB.m` | SNOTEL station locations within a region |
| `plotSNODAS_BRB.py` | `plotSNODAS_BRB.m` | 6-figure SNODAS visualization suite |
| `plotUCLA_SR_BRB.py` | `plotUCLA_SR_BRB.m` | 6-figure UCLA SR visualization suite |
| `plotSnowVar.py` | `plotSnowVar.m` | Generic single-date snow map |
| `makeSnowMovie.py` | `makeSnowMovie.m` | Generic MP4 movie maker |
| `movieSNODAS_BRB.py` | `movieSNODAS_BRB.m` | Quick SNODAS animation |
| `snowViz.py` | `snowViz.m` | Interactive menu-driven visualization driver |
| `compareSWE_movie.py` | `compareSWE_movie.m` | Side-by-side SNODAS vs UCLA SWE movie |
| `earthdata_credentials.py` | `earthdata_credentials.m` | Manage NASA Earthdata credentials via `~/.netrc` |
| `diagnoseTiles.py` | `diagnoseTiles.m` | Diagnostic checks on UCLA tile coordinate ordering |

### Python Quick Start

```bash
# Download SNODAS (edit WY and paths at top of script first)
python python/getSNODAS_BRB.py

# Download UCLA SR tiles
python python/getUCLA_SR_BRB.py

# Generate SNODAS figures (default: April 1 of the water year)
python python/plotSNODAS_BRB.py

# Generate UCLA SR figures (default: April 1 of the water year)
python python/plotUCLA_SR_BRB.py

# Side-by-side SWE comparison movie
python python/compareSWE_movie.py
```

### Python Visualization Options

#### `plotSNODAS_BRB.py`

```
usage: plotSNODAS_BRB.py [--wy WY] [--date YYYY-MM-DD] [--month M] [--day D]
                          [--data-root DIR] [--out-dir DIR] [--no-utm]
```

| Argument | Default | Description |
|---|---|---|
| `--wy` | `2021` | Water year |
| `--date YYYY-MM-DD` | April 1 of `--wy` | Target date for snapshot figures |
| `--month`, `--day` | `4`, `1` | Alternative to `--date`; ignored if `--date` given |
| `--data-root DIR` | `/Users/hpmarshall/DATA_DRIVE/SnowFusion` | Root of data directory tree |
| `--out-dir DIR` | same as data directory | Where to write output PNG files |
| `--no-utm` | — | Use geographic (lat/lon) coords instead of UTM |

```bash
# Default: WY2021, April 1, UTM coordinates
python python/plotSNODAS_BRB.py

# Specific date
python python/plotSNODAS_BRB.py --date 2021-03-15

# Different water year and date
python python/plotSNODAS_BRB.py --wy 2020 --date 2020-04-01

# Save figures to a custom directory
python python/plotSNODAS_BRB.py --date 2021-04-01 --out-dir ~/Desktop/snodas_figs

# Geographic coordinates instead of UTM
python python/plotSNODAS_BRB.py --date 2021-04-01 --no-utm
```

All six figures are displayed interactively after saving. Close the figure windows to exit.

---

#### `plotUCLA_SR_BRB.py`

```
usage: plotUCLA_SR_BRB.py [--wy-str WY_STR] [--wy-start-year YEAR]
                           [--lat-tiles N [N ...]] [--lon-tiles N [N ...]]
                           [--date YYYY-MM-DD] [--target-date N]
                           [--ens-idx N] [--data-dir DIR] [--out-dir DIR] [--no-utm]
```

| Argument | Default | Description |
|---|---|---|
| `--wy-str` | `WY2020_21` | Water year string matching tile filenames |
| `--wy-start-year` | `2020` | Calendar year when the water year starts (Oct 1) |
| `--lat-tiles N …` | `43 44` | Tile lower-left latitudes to mosaic |
| `--lon-tiles N …` | `115 116 117` | Tile lower-left west longitudes to mosaic |
| `--date YYYY-MM-DD` | April 1 of the water year | Target date for snapshot figures |
| `--target-date N` | `183` | Day of water year (1 = Oct 1); ignored if `--date` given |
| `--ens-idx N` | `0` | Ensemble member index (0=mean, 1=std, 2=25th, 3=median, 4=75th) |
| `--data-dir DIR` | `.../UCLA_SR` | Directory containing downloaded `.nc` tiles |
| `--out-dir DIR` | same as data directory | Where to write output PNG files |
| `--std-clim N` | auto (data max) | Upper color limit for the SWE uncertainty map [cm] |
| `--no-utm` | — | Use geographic (lat/lon) coords instead of UTM |

```bash
# Default: WY2020_21, April 1, UTM coordinates
python python/plotUCLA_SR_BRB.py

# Specific date
python python/plotUCLA_SR_BRB.py --date 2021-03-15

# Save figures to a custom directory
python python/plotUCLA_SR_BRB.py --date 2021-04-01 --out-dir ~/Desktop/ucla_figs

# Show ensemble median instead of mean
python python/plotUCLA_SR_BRB.py --date 2021-04-01 --ens-idx 3

# Different tile coverage (e.g. single 1-degree tile)
python python/plotUCLA_SR_BRB.py --lat-tiles 43 --lon-tiles 116 --date 2021-04-01

# Limit SWE uncertainty color scale to 10 cm to reveal spatial variation
python python/plotUCLA_SR_BRB.py --date 2021-04-01 --std-clim 10
```

All six figures are displayed interactively after saving. Close the figure windows to exit.

### Required Python Packages

Install all dependencies with:

```bash
pip install numpy matplotlib scipy netCDF4 requests imageio imageio-ffmpeg geopandas pyproj shapely
```

Or with conda:

```bash
conda install numpy matplotlib scipy netCDF4 requests imageio geopandas pyproj shapely
pip install imageio-ffmpeg
```

| Package | Version | Purpose |
|---|---|---|
| `numpy` | ≥1.22 | Array operations |
| `matplotlib` | ≥3.5 | Plotting and figure export |
| `scipy` | ≥1.7 | Loading MATLAB `.mat` files (`scipy.io`) |
| `netCDF4` | ≥1.5 | Reading UCLA SR `.nc` tiles |
| `requests` | ≥2.27 | HTTPS download of SNODAS data |
| `imageio` | ≥2.16 | MP4 movie writing |
| `imageio-ffmpeg` | any | FFmpeg backend for imageio |
| `geopandas` | ≥0.10 | Reading shapefiles (BRB outline, SNOTEL) |
| `pyproj` | ≥3.2 | UTM ↔ geographic coordinate conversion |
| `shapely` | ≥1.8 | Point-in-polygon tests for SNOTEL filtering |

Python ≥ 3.9 is required.

---

## Data Structures

Both data sources return structures with compatible field naming so that the generic visualization functions (`plotSnowVar`, `makeSnowMovie`) work interchangeably.

### SNODAS Structure

```
Snodas.WY            - Water year (scalar)
Snodas.lat           - Latitude vector [nLat x 1] (north to south)
Snodas.lon           - Longitude vector [1 x nLon] (west to east)
Snodas.dates         - Datenum vector [1 x nDays]
Snodas.datestr       - Cell array of date strings
Snodas.SWE           - Snow water equivalent [m]       (nLat x nLon x nDays)
Snodas.Depth         - Snow depth [m]                   (nLat x nLon x nDays)
Snodas.Precip        - Liquid precipitation [kg/m^2]    (nLat x nLon x nDays)
Snodas.SnowPrecip    - Solid precipitation [kg/m^2]     (nLat x nLon x nDays)
Snodas.Tsnow         - Snowpack temperature [K]         (nLat x nLon x nDays)
Snodas.Melt          - Snowmelt [m]                     (nLat x nLon x nDays)
Snodas.Sublimation   - Pack sublimation [m]             (nLat x nLon x nDays)
Snodas.SublimationBS - Blowing snow sublimation [m]     (nLat x nLon x nDays)
```

Python equivalent: dict with the same keys; arrays are `numpy.ndarray`; dates are `list[datetime.date]`.

### UCLA Structure

```
UCLA.WY              - Water year (scalar)
UCLA.lat             - Latitude vector [nLat x 1]
UCLA.lon             - Longitude vector [1 x nLon]
UCLA.dates           - Datenum vector [1 x nDays]
UCLA.datestr         - Cell array of date strings
UCLA.SWE_mean        - SWE ensemble mean [m]            (nLat x nLon x nDays)
UCLA.SWE_std         - SWE ensemble std dev [m]         (nLat x nLon x nDays)
UCLA.SWE_median      - SWE ensemble median [m]          (nLat x nLon x nDays)
UCLA.SWE_p25         - SWE 25th percentile [m]          (nLat x nLon x nDays)
UCLA.SWE_p75         - SWE 75th percentile [m]          (nLat x nLon x nDays)
UCLA.fSCA_mean       - Fractional snow cover [-]         (nLat x nLon x nDays)
UCLA.SD_mean         - Snow depth mean [m]               (nLat x nLon x nDays)
UCLA.SD_std          - Snow depth std dev [m]            (nLat x nLon x nDays)
UCLA.SD_median       - Snow depth median [m]             (nLat x nLon x nDays)
```

Python equivalent: dict with the same keys; arrays are `numpy.ndarray`; dates are `list[datetime.date]`.

---

## Requirements

### MATLAB

- MATLAB R2019b or later
- Mapping Toolbox (for `usamap`, `geoshow`, `shaperead`, `projcrs`, UTM conversions)
- Internet connection (for data downloads)
- NASA Earthdata account (for UCLA SR data only; register at https://urs.earthdata.nasa.gov)

### Python

- Python ≥ 3.9
- See [Required Python Packages](#required-python-packages) above
- NASA Earthdata account (for UCLA SR data only)

---

## Boise River Basin Bounding Box

The default region for all scripts is the Boise River Basin in central Idaho:

```
Latitude:  43.0 to 45.0 deg N
Longitude: -117.0 to -114.0 deg E
```

The BRB shapefile (`BRB_outline.shp`) is in UTM Zone 11N (NAD83). All scripts handle the UTM-to-geographic coordinate conversion automatically. SNOTEL sites are read from `SNOTEL/IDDCO_2020_automated_sites.shp` and filtered to whatever spatial extent is currently being plotted.

---

## File List

| File | Type | Language | Description |
|------|------|----------|-------------|
| `getSNODAS_BRB.m` | Script | MATLAB | SNODAS HTTPS downloader for BRB water year |
| `getSNODAS_WY.m` | Function | MATLAB | SNODAS FTP downloader (alternate, any region) |
| `loadSNODAS_var.m` | Function | MATLAB | Load single variable from cached .mat files |
| `getUCLA_SR_BRB.m` | Script | MATLAB | UCLA SR NetCDF tile downloader for BRB |
| `mosaicUCLA_SR.m` | Function | MATLAB | Mosaic 1-deg UCLA tiles into continuous grid |
| `getUCLA_SWE.m` | Function | MATLAB | Load UCLA tiles with ensemble statistics |
| `getSNOTEL_BRB.m` | Function | MATLAB | SNOTEL station locations within a region |
| `plotSNODAS_BRB.m` | Script | MATLAB | 6-figure SNODAS visualization suite |
| `plotUCLA_SR_BRB.m` | Script | MATLAB | 6-figure UCLA SR visualization suite |
| `plotSnowVar.m` | Function | MATLAB | Generic single-date snow map (both sources) |
| `makeSnowMovie.m` | Function | MATLAB | Generic MP4 movie maker (both sources) |
| `movieSNODAS_BRB.m` | Script | MATLAB | Quick SNODAS variable animation |
| `snowViz.m` | Script | MATLAB | Interactive menu-driven visualization driver |
| `compareSWE_movie.m` | Script | MATLAB | Side-by-side SNODAS vs UCLA SWE movie |
| `earthdata_credentials.m` | Script | MATLAB | Local NASA Earthdata credentials (not in git) |
| `diagnoseTiles.m` | Script | MATLAB | Diagnostic checks on UCLA tile coordinates |
| `python/getSNODAS_BRB.py` | Script | Python | — same as MATLAB equivalent — |
| `python/getSNODAS_WY.py` | Function | Python | — |
| `python/loadSNODAS_var.py` | Function | Python | — |
| `python/getUCLA_SR_BRB.py` | Script | Python | — |
| `python/mosaicUCLA_SR.py` | Function | Python | — |
| `python/getUCLA_SWE.py` | Function | Python | — |
| `python/getSNOTEL_BRB.py` | Function | Python | — |
| `python/plotSNODAS_BRB.py` | Script | Python | — |
| `python/plotUCLA_SR_BRB.py` | Script | Python | — |
| `python/plotSnowVar.py` | Function | Python | — |
| `python/makeSnowMovie.py` | Function | Python | — |
| `python/movieSNODAS_BRB.py` | Script | Python | — |
| `python/snowViz.py` | Script | Python | — |
| `python/compareSWE_movie.py` | Script | Python | — |
| `python/earthdata_credentials.py` | Module | Python | Credentials via ~/.netrc (not in git) |
| `python/diagnoseTiles.py` | Script | Python | — |
