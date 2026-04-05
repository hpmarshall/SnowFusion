% getSNODAS_BRB.m
% Downloads SNODAS (G02158) data for the Boise River Basin from NSIDC
% using HTTPS (replacing legacy FTP access to sidads.colorado.edu).
%
% Dataset: https://nsidc.org/data/g02158/versions/1
% Resolution: ~1 km (30 arc-sec), daily, 2003-present
% Variables (8 total):
%   1025SlL00 - Precipitation (liquid, kg/m^2)
%   1025SlL01 - Snowfall (solid precip, kg/m^2)
%   1034      - Snow Water Equivalent (m * 1000)
%   1036      - Snow Depth (m * 1000)
%   1038      - Snow pack average temperature (K * 1)
%   1039      - Blowing snow sublimation (m * 100000)
%   1044      - Snow melt (m * 100000)
%   1050      - Snow pack sublimation (m * 100000)
%
% Grid: 6935 x 3351 pixels, flat binary int16, big-endian
% Bounding box: lon [-124.7337, -66.9421], lat [24.9496, 52.8746]
%
% Based on original getSNODAS.m and getSNODASall.m by HP Marshall
% Updated to use HTTPS access, April 2026
%
% Companion scripts:
%   plotSNODAS_BRB.m  - Visualize downloaded data (maps, time series, movies)
%   getSNODAS_WY.m    - Alternative FTP-based downloader (full function)
%   snowViz.m         - Interactive visualization driver
%
% HP Marshall, Boise State University

clear; clc;

%% ====== USER CONFIGURATION ======
% Water year(s) to download
% SNODAS archive begins Oct 2003 (WY2004)
WY = 2021;  % Water year to download (e.g. 2021 = Oct 2020 - Sep 2021)

% Output directory (external data drive - keeps large files out of git repo)
dataRoot = '/Users/hpmarshall/DATA_DRIVE/SnowFusion';
outDir = fullfile(dataRoot, 'SNODAS');
if ~exist(outDir, 'dir'); mkdir(outDir); end

% Temporary directory for extracting tar/gz files
tempDir = fullfile(dataRoot, 'temp_download');
if ~exist(tempDir, 'dir'); mkdir(tempDir); end

%% ====== SNODAS GRID DEFINITION ======
% Full CONUS grid parameters (from SNODAS documentation)
lonmin = -124.733749999999;
lonmax = -66.9420833333342;
latmin = 24.9495833333335;
latmax = 52.8745833333323;
nCols  = 6935;
nRows  = 3351;

lon = linspace(lonmin, lonmax, nCols);
lat = linspace(latmax, latmin, nRows); % north to south

% Bounding box matching UCLA SR tile coverage (latTiles=[43,44], lonTiles=[115,116,117])
% Tiles named by SW corner: W115=[-115,-114], W116=[-116,-115], W117=[-117,-116]
BRB_lat = [43.0 45.0];
BRB_lon = [-117.0 -114.0];

% Find pixel indices for BRB subset
Ix = find(lon >= BRB_lon(1) & lon <= BRB_lon(2));
Iy = find(lat >= BRB_lat(1) & lat <= BRB_lat(2));
lon_sub = lon(Ix);
lat_sub = lat(Iy);

fprintf('BRB subset: %d x %d pixels\n', length(Iy), length(Ix));

%% ====== SNODAS PRODUCT DEFINITIONS ======
% Product codes (used to match filenames inside tar archives)
prodCode = {'1025SlL00', '1025SlL01', '1034', '1036', '1038', '1039', '1044', '1050'};
prodName = {'Precip', 'SnowPrecip', 'SWE', 'Depth', 'Tsnow', 'SublimationBS', 'Melt', 'Sublimation'};
nVars = length(prodCode);

%% ====== BUILD DATE LIST FOR WATER YEAR ======
% Water year runs Oct 1 (year-1) through Sep 30 (year)
startDate = datenum(WY-1, 10, 1);
endDate   = datenum(WY, 9, 30);
allDates  = startDate:endDate;
nDays     = length(allDates);

fprintf('Water Year %d: %s to %s (%d days)\n', WY, ...
    datestr(startDate, 'yyyy-mm-dd'), datestr(endDate, 'yyyy-mm-dd'), nDays);

%% ====== INITIALIZE OUTPUT STRUCTURE ======
Snodas.WY = WY;
Snodas.lat = lat_sub;
Snodas.lon = lon_sub;
Snodas.dates = allDates;
Snodas.datestr = cellstr(datestr(allDates, 'yyyy-mm-dd'));
for v = 1:nVars
    Snodas.(prodName{v}) = NaN(length(Iy), length(Ix), nDays);
end

%% ====== HTTPS BASE URL ======
% NSIDC now serves SNODAS via HTTPS (no authentication required)
% Directory structure: /NOAA/G02158/masked/YYYY/MM_Mon/
baseURL = 'https://noaadata.apps.nsidc.org/NOAA/G02158/masked/';

%% ====== MAIN DOWNLOAD LOOP ======
fprintf('\n=== Downloading SNODAS data for WY%d ===\n', WY);

for d = 1:nDays
    dv = datevec(allDates(d));
    yyyy = dv(1);
    mm   = dv(2);
    dd   = dv(3);

    % Build month directory name (e.g., "01_Jan", "10_Oct")
    monthNames = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
    monthDir = sprintf('%02d_%s', mm, monthNames{mm});

    % Build tar filename
    % Convention: SNODAS_YYYYMMDD.tar
    tarName = sprintf('SNODAS_%04d%02d%02d.tar', yyyy, mm, dd);

    % Check if we already have saved .mat file for this date
    matFile = fullfile(outDir, sprintf('SNODAS_BRB_%04d%02d%02d.mat', yyyy, mm, dd));
    if exist(matFile, 'file')
        % Load existing data - check grid size matches current bounding box
        R = load(matFile);
        firstVar = prodName{find(isfield(R, prodName), 1)};
        if ~isempty(firstVar) && ~isequal(size(R.(firstVar)), [length(Iy) length(Ix)])
            fprintf('  [%d/%d] %s - cache size mismatch, re-downloading\n', d, nDays, datestr(allDates(d)));
            delete(matFile);
        else
            for v = 1:nVars
                if isfield(R, prodName{v})
                    Snodas.(prodName{v})(:,:,d) = R.(prodName{v});
                end
            end
            if mod(d, 30) == 0
                fprintf('  [%d/%d] %s - loaded from cache\n', d, nDays, datestr(allDates(d)));
            end
            continue;
        end
    end

    % Build URL
    url = sprintf('%s%04d/%s/%s', baseURL, yyyy, monthDir, tarName);

    fprintf('  [%d/%d] %s ... ', d, nDays, datestr(allDates(d)));

    % Download tar file
    tarFile = fullfile(tempDir, tarName);
    try
        websave(tarFile, url, weboptions('Timeout', 120));
    catch ME
        fprintf('FAILED: %s\n', ME.message);
        continue;
    end

    % Extract tar
    try
        untar(tarFile, tempDir);
        delete(tarFile);
    catch ME
        fprintf('UNTAR FAILED: %s\n', ME.message);
        continue;
    end

    % Process each variable
    dayData = struct();
    for v = 1:nVars
        % Find the .dat.gz file matching this product code
        gzFiles = dir(fullfile(tempDir, ['*' prodCode{v} '*.dat.gz']));
        if isempty(gzFiles)
            continue;
        end

        % Unzip
        gzPath = fullfile(tempDir, gzFiles(1).name);
        gunzip(gzPath);
        delete(gzPath);

        % Find the .dat file
        datFiles = dir(fullfile(tempDir, ['*' prodCode{v} '*.dat']));
        if isempty(datFiles)
            continue;
        end

        % Read binary data: int16, big-endian, 6935 x 3351
        datPath = fullfile(tempDir, datFiles(1).name);
        fid = fopen(datPath, 'r', 'b');  % 'b' = big-endian
        D = fread(fid, [nCols nRows], 'int16');
        fclose(fid);
        D = D';  % transpose to [rows x cols]

        % Subset to BRB
        D_sub = D(Iy, Ix);

        % Store in structure
        Snodas.(prodName{v})(:,:,d) = D_sub;
        dayData.(prodName{v}) = D_sub;

        delete(datPath);
    end

    % Clean up remaining temp files (headers, etc.)
    tempFiles = dir(fullfile(tempDir, '*'));
    for tf = 1:length(tempFiles)
        if ~tempFiles(tf).isdir
            delete(fullfile(tempDir, tempFiles(tf).name));
        end
    end

    % Save individual day .mat file for caching
    dayData.date = allDates(d);
    dayData.lat = lat_sub;
    dayData.lon = lon_sub;
    save(matFile, '-struct', 'dayData');

    fprintf('OK\n');
end

%% ====== SET NO-DATA TO NaN (BEFORE UNIT CONVERSION) ======
fprintf('\nCleaning no-data values...\n');
% SNODAS uses -9999 as fill value in raw int16 data
for v = 1:nVars
    D = Snodas.(prodName{v});
    D(D == -9999) = NaN;
    Snodas.(prodName{v}) = D;
end

%% ====== CONVERT UNITS ======
fprintf('Converting units...\n');

% Precipitation fields: raw values in kg/m^2 scaled by 10
% i.e., value of 100 = 10.0 kg/m^2 = 10.0 mm
Snodas.Precip     = Snodas.Precip / 10;         % -> kg/m^2 (= mm)
Snodas.SnowPrecip = Snodas.SnowPrecip / 10;     % -> kg/m^2 (= mm w.e.)

% SWE and Depth: raw values in meters * 1000
Snodas.SWE   = Snodas.SWE / 1000;    % -> meters
Snodas.Depth = Snodas.Depth / 1000;   % -> meters

% Temperature: raw in Kelvin (no scale factor)
% Snodas.Tsnow stays in Kelvin

% Sublimation and Melt: raw in meters * 100000
Snodas.SublimationBS = Snodas.SublimationBS / 1e5;  % -> meters
Snodas.Sublimation   = Snodas.Sublimation / 1e5;    % -> meters
Snodas.Melt          = Snodas.Melt / 1e5;           % -> meters

%% ====== SAVE COMPLETE WATER YEAR ======
outFile = fullfile(outDir, sprintf('SNODAS_BRB_WY%d.mat', WY));
save(outFile, 'Snodas', '-v7.3');
fprintf('\nSaved: %s\n', outFile);

%% ====== SUMMARY ======
fprintf('\n=== Download Summary ===\n');
fprintf('Water Year: %d\n', WY);
fprintf('Region: Boise River Basin (%d x %d pixels)\n', length(Iy), length(Ix));
fprintf('Variables:\n');
for v = 1:nVars
    nValid = sum(~isnan(Snodas.(prodName{v})(:)));
    nTotal = numel(Snodas.(prodName{v}));
    fprintf('  %s: %.1f%% valid data\n', prodName{v}, 100*nValid/nTotal);
end
% Quick peek: April 1 SWE
apr1 = datenum(WY, 4, 1);
[~, apr1Idx] = min(abs(Snodas.dates - apr1));
apr1SWE = Snodas.SWE(:,:,apr1Idx);
fprintf('\nApril 1 basin statistics:\n');
fprintf('  Mean SWE:  %.1f cm\n', nanmean(apr1SWE(:)) * 100);
fprintf('  Max SWE:   %.1f cm\n', max(apr1SWE(:), [], 'omitnan') * 100);
apr1Depth = Snodas.Depth(:,:,apr1Idx);
fprintf('  Mean Depth: %.1f cm\n', nanmean(apr1Depth(:)) * 100);
fprintf('  Max Depth:  %.1f cm\n', max(apr1Depth(:), [], 'omitnan') * 100);

fprintf('\nOutput file: %s (%.1f MB)\n', outFile, dir(outFile).bytes / 1e6);
fprintf('\nDone! Run plotSNODAS_BRB.m to visualize.\n');
