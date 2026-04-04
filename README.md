# SnowFusion

MATLAB tools for downloading, processing, and visualizing gridded snow products over the Boise River Basin (BRB). Combines two complementary data sources: NOAA's Snow Data Assimilation System (SNODAS) and the UCLA Western US Snow Reanalysis (WUS_UCLA_SR).

**Author:** HP Marshall, Boise State University
**Created:** April 2026

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
  getSNOTEL_BRB.m       Function: returns SNOTEL station locations in the BRB

  -- Visualization --
  plotSNODAS_BRB.m      Script: 6 publication-quality figures from SNODAS data
  plotUCLA_SR_BRB.m     Script: 6 publication-quality figures from UCLA SR data
  plotSnowVar.m         Function: generic single-date map for any snow variable
  makeSnowMovie.m       Function: generic MP4 movie for any snow variable
  movieSNODAS_BRB.m     Script: quick SNODAS animation with variable selection
  snowViz.m             Script: interactive menu-driven visualization driver

  -- Subdirectories (legacy/original code) --
  SNODAS/               Original SNODAS scripts and earlier versions
  UCLA_SR/              Original UCLA SR scripts
  .gitignore            Excludes data files from git

External data directory (not in git repo):
  /Users/hpmarshall/DATA_DRIVE/SnowFusion/
    SNODAS/             Downloaded SNODAS .mat files and figures
    UCLA_SR/            Downloaded UCLA .nc files and figures
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

Edit `getUCLA_SR_BRB.m` with your NASA Earthdata credentials, then run:

```matlab
>> getUCLA_SR_BRB
```

This downloads the 1-deg x 1-deg NetCDF tiles covering the BRB. If automated download fails, the script prints manual download instructions via NSIDC's Data Access Tool.

### 3. Visualize SNODAS Data

After downloading, run:

```matlab
>> plotSNODAS_BRB
```

This generates 6 figures:

1. SWE map (April 1 by default) in cm
2. Snow depth map in cm
3. Daily melt map in mm
4. 3-panel summary (SWE, depth, melt)
5. Time series of basin-mean SWE and depth over the water year
6. SWE vs. snow depth scatter with bulk density analysis

### 4. Visualize UCLA Snow Reanalysis Data

```matlab
>> plotUCLA_SR_BRB
```

This generates 6 figures:

1. SWE map (ensemble mean, April 1) in cm
2. Fractional snow-covered area map in percent
3. Snow depth map in cm
4. 3-panel summary (SWE, fSCA, depth)
5. Time series of basin-mean SWE with ensemble uncertainty envelope
6. SWE uncertainty map (ensemble standard deviation)

### 5. Interactive Visualization

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

#### `getSNOTEL_BRB()`

Return SNOTEL station locations for the Boise River Basin. Returns a structure with 9 verified stations (from the NRCS National Water and Climate Center) including name, site number, latitude, longitude, and elevation.

```matlab
snotel = getSNOTEL_BRB();
fprintf('%d stations loaded\n', snotel.nStations);

% Plot stations on a map
plot(snotel.lon, snotel.lat, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
```

**Output:** Structure with fields `.name` (cell array), `.siteNum`, `.lat`, `.lon`, `.elev_ft`, `.nStations`

**Stations:** Atlanta Summit (306), Banner Summit (312), Deadwood Summit (436), Graham Guard Sta. (496), Jackson Peak (550), Mores Creek Summit (637), Prairie (710), Trinity Mountain (830), Bogus Basin (978)

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

% Plot fractional snow cover
plotSnowVar(UCLA, 'fSCA_mean', '2020-03-15');
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

---

## Requirements

- MATLAB R2019b or later
- Mapping Toolbox (for `usamap`, `geoshow`, `shaperead`, UTM conversions)
- Internet connection (for data downloads)
- NASA Earthdata account (for UCLA SR data only; register at https://urs.earthdata.nasa.gov)

---

## Boise River Basin Bounding Box

The default region for all scripts is the Boise River Basin in central Idaho:

```
Latitude:  43.0 to 44.5 deg N
Longitude: -116.3 to -114.3 deg E
```

The BRB shapefile (`BRB_outline.shp`) is in UTM Zone 11N (NAD83). All scripts handle the UTM-to-geographic coordinate conversion automatically.

---

## File List: New and Modified (April 2--3, 2026)

| File | Type | Description |
|------|------|-------------|
| `getSNODAS_BRB.m` | Script | SNODAS HTTPS downloader for BRB water year |
| `getSNODAS_WY.m` | Function | SNODAS FTP downloader (alternate, any region) |
| `loadSNODAS_var.m` | Function | Load single variable from cached .mat files |
| `getUCLA_SR_BRB.m` | Script | UCLA SR NetCDF tile downloader for BRB |
| `mosaicUCLA_SR.m` | Function | Mosaic 1-deg UCLA tiles into continuous grid |
| `getUCLA_SWE.m` | Function | Load UCLA tiles with ensemble statistics |
| `getSNOTEL_BRB.m` | Function | SNOTEL station locations for the BRB (9 stations) |
| `plotSNODAS_BRB.m` | Script | 6-figure SNODAS visualization suite |
| `plotUCLA_SR_BRB.m` | Script | 6-figure UCLA SR visualization suite |
| `plotSnowVar.m` | Function | Generic single-date snow map (works with both sources) |
| `makeSnowMovie.m` | Function | Generic MP4 movie maker (works with both sources) |
| `movieSNODAS_BRB.m` | Script | Quick SNODAS variable animation |
| `snowViz.m` | Script | Interactive menu-driven visualization driver |
