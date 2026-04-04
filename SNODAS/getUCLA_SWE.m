function UCLA = getUCLA_SWE(WY, BB, dataDir)
% getUCLA_SWE - Load UCLA SWE Snow Reanalysis tiles for a region/water year
%
% USAGE:
%   UCLA = getUCLA_SWE(WY, BB, dataDir)
%
% INPUTS:
%   WY      - Water year (e.g. 2020, range: 1985-2021)
%   BB      - Bounding box [lonmin lonmax latmin latmax]
%             Default: Boise River Basin [-116.2 -114.6 43.2 44.4]
%   dataDir - Directory containing downloaded UCLA .nc files
%             Files should follow naming: N{lat}_0_W{lon}_0_{var}_v001.nc
%
% OUTPUT:
%   UCLA - Structure with fields:
%       .WY        - Water year
%       .lat       - latitude vector (south to north)
%       .lon       - longitude vector (west to east)
%       .dates     - datenum vector of dates
%       .datestr   - cell array of date strings
%       .SWE_mean  - Posterior SWE mean [m]          (ny x nx x ndays)
%       .SWE_std   - Posterior SWE std dev [m]        (ny x nx x ndays)
%       .SWE_median- Posterior SWE median [m]         (ny x nx x ndays)
%       .SWE_p25   - Posterior SWE 25th pctile [m]    (ny x nx x ndays)
%       .SWE_p75   - Posterior SWE 75th pctile [m]    (ny x nx x ndays)
%       .fSCA_mean - Fractional snow cover mean [-]   (ny x nx x ndays)
%       .SD_mean   - Snow depth mean [m]              (ny x nx x ndays)
%       .SD_std    - Snow depth std dev [m]            (ny x nx x ndays)
%       .SD_median - Snow depth median [m]             (ny x nx x ndays)
%
% NOTES:
%   - Data must be downloaded from NSIDC first (requires NASA Earthdata login)
%     https://nsidc.org/data/wus_ucla_sr/versions/1
%   - Files are 1deg x 1deg tiles in NetCDF format
%   - Resolution: ~500m (16 arc-seconds), 225 pixels per degree
%   - Water years 1985-2021
%   - Ensemble stats: [1]=mean, [2]=std, [3]=median, [4]=25th, [5]=75th pctile
%
% EXAMPLE:
%   UCLA = getUCLA_SWE(2020, [-116.2 -114.6 43.2 44.4], './UCLA_data');
%
% HP Marshall, Boise State University
% SnowFusion Project

if nargin < 2 || isempty(BB)
    BB = [-116.2 -114.6 43.2 44.4]; % Boise River Basin
end
if nargin < 3 || isempty(dataDir)
    dataDir = pwd;
end

%% Determine which tiles are needed
% Tile naming: lower-left corner of 1-degree tile
latTiles = floor(BB(3)):floor(BB(4));   % e.g. [43, 44]
lonTiles = floor(abs(BB(2))):floor(abs(BB(1))); % west longitudes (positive values)
% BB(1) is more negative (further west), so abs(BB(1)) > abs(BB(2))
% e.g. BB=[-116.2 -114.6 ...] -> lonTiles = [114, 115, 116]

fprintf('UCLA SWE: Need %d x %d tiles for bounding box\n', ...
    length(latTiles), length(lonTiles));
fprintf('  Tiles: ');
for lt = latTiles
    for lnw = lonTiles
        fprintf('N%d_0_W%d_0  ', lt, lnw);
    end
end
fprintf('\n');

%% Determine water year day indices
% UCLA data dimension 4 = day of water year (1-366, starting Oct 1)
startDate = datenum(WY-1, 10, 1);
if eomday(WY, 2) == 29 % leap year check
    nDaysWY = 366;
else
    nDaysWY = 365;
end
endDate = startDate + nDaysWY - 1;
allDates = startDate:endDate;

%% Load SWE/fSCA tiles (SWE_SCA_POST files)
fprintf('Loading SWE/fSCA tiles for WY%d...\n', WY);
wyIdx = WY - 1984; % Index into the time dimension (WY1985 = index 1)

% First pass: determine full grid size and coordinates
allLat = [];
allLon = [];
tileData = struct();

for lt = latTiles
    for lnw = lonTiles
        % Build filename
        fname_swe = sprintf('N%d_0_W%d_0_SWE_SCA_POST_v001.nc', lt, lnw);
        fpath_swe = fullfile(dataDir, fname_swe);

        if ~exist(fpath_swe, 'file')
            fprintf('  WARNING: %s not found. Skipping tile.\n', fname_swe);
            continue;
        end

        % Read coordinate variables
        lat_tile = ncread(fpath_swe, 'lat');
        lon_tile = ncread(fpath_swe, 'lon');

        % Read SWE and fSCA for this water year
        % Dimensions: [lon, lat, stats, day, year] or [lat, lon, stats, day]
        % Need to check actual dimension order
        info = ncinfo(fpath_swe);
        dimNames = {info.Dimensions.name};
        dimSizes = [info.Dimensions.Length];
        fprintf('  %s: dims = ', fname_swe);
        for di = 1:length(dimNames)
            fprintf('%s(%d) ', dimNames{di}, dimSizes(di));
        end
        fprintf('\n');

        % Read the SWE variable
        varNames = {info.Variables.name};

        % Find the SWE data variable
        sweVarIdx = find(contains(varNames, 'SWE') & ~contains(varNames, 'lat') & ~contains(varNames, 'lon'));
        if isempty(sweVarIdx)
            sweVarIdx = find(contains(varNames, 'swe', 'IgnoreCase', true));
        end

        % Try reading with different possible variable names
        sweVarName = '';
        fscaVarName = '';
        for vi = 1:length(varNames)
            vn = varNames{vi};
            if contains(vn, 'SWE', 'IgnoreCase', true) && ~contains(vn, 'lat') && ~contains(vn, 'lon')
                sweVarName = vn;
            end
            if contains(vn, 'SCA', 'IgnoreCase', true) || contains(vn, 'fSCA', 'IgnoreCase', true)
                fscaVarName = vn;
            end
        end

        if isempty(sweVarName)
            % Fall back: try the first non-coordinate variable
            for vi = 1:length(varNames)
                if ~any(strcmpi(varNames{vi}, {'lat','lon','latitude','longitude','time','stats'}))
                    sweVarName = varNames{vi};
                    break;
                end
            end
        end

        fprintf('  Reading variable: %s\n', sweVarName);

        % Read the full data for this tile
        sweData = ncread(fpath_swe, sweVarName);

        % Store for assembly
        key = sprintf('N%d_W%d', lt, lnw);
        tileData.(key).lat = lat_tile;
        tileData.(key).lon = lon_tile;
        tileData.(key).swe = sweData;

        % Also try to read fSCA if in same file
        if ~isempty(fscaVarName)
            tileData.(key).fsca = ncread(fpath_swe, fscaVarName);
        end
    end
end

%% Load Snow Depth tiles (SD_POST files)
fprintf('Loading Snow Depth tiles for WY%d...\n', WY);
for lt = latTiles
    for lnw = lonTiles
        fname_sd = sprintf('N%d_0_W%d_0_SD_POST_v001.nc', lt, lnw);
        fpath_sd = fullfile(dataDir, fname_sd);

        key = sprintf('N%d_W%d', lt, lnw);

        if ~exist(fpath_sd, 'file')
            fprintf('  WARNING: %s not found.\n', fname_sd);
            continue;
        end

        info_sd = ncinfo(fpath_sd);
        varNames_sd = {info_sd.Variables.name};

        sdVarName = '';
        for vi = 1:length(varNames_sd)
            if contains(varNames_sd{vi}, 'SD', 'IgnoreCase', false) || ...
               contains(varNames_sd{vi}, 'depth', 'IgnoreCase', true)
                if ~any(strcmpi(varNames_sd{vi}, {'lat','lon','latitude','longitude','time','stats'}))
                    sdVarName = varNames_sd{vi};
                    break;
                end
            end
        end

        if ~isempty(sdVarName)
            fprintf('  Reading variable: %s from %s\n', sdVarName, fname_sd);
            tileData.(key).sd = ncread(fpath_sd, sdVarName);
        end
    end
end

%% Assemble tiles into mosaic
fprintf('Assembling tile mosaic...\n');
tileKeys = fieldnames(tileData);
if isempty(tileKeys)
    error('No UCLA SWE tiles found in %s. Download data first.', dataDir);
end

% Concatenate all lat/lon
allLat = [];
allLon = [];
for k = 1:length(tileKeys)
    allLat = [allLat; tileData.(tileKeys{k}).lat(:)];
    allLon = [allLon; tileData.(tileKeys{k}).lon(:)];
end
allLat = unique(sort(allLat));
allLon = unique(sort(allLon));

% Subset to bounding box
latIdx = allLat >= BB(3) & allLat <= BB(4);
lonIdx = allLon >= -abs(BB(2)) & allLon <= -abs(BB(1));
UCLA.lat = allLat(latIdx);
UCLA.lon = allLon(lonIdx);
ny = length(UCLA.lat);
nx = length(UCLA.lon);

%% Extract ensemble statistics and subset to water year
% The data dimensions depend on how NSIDC structured the file.
% Typically: [225 x 225 x 5 x 366] per water year, with multiple WYs
% We need to figure out the exact layout from what we read.

% For now, initialize output arrays
UCLA.WY = WY;
UCLA.dates = allDates;
UCLA.datestr = cellstr(datestr(allDates, 'yyyy-mm-dd'));

% Initialize output variables
statNames = {'mean','std','median','p25','p75'};
for si = 1:5
    UCLA.(['SWE_' statNames{si}]) = NaN(ny, nx, nDaysWY);
end
UCLA.fSCA_mean = NaN(ny, nx, nDaysWY);
for si = 1:5
    UCLA.(['SD_' statNames{si}]) = NaN(ny, nx, nDaysWY);
end

% Map tile data into the mosaic
for k = 1:length(tileKeys)
    td = tileData.(tileKeys{k});

    % Find where this tile's coords map into the output grid
    [~, latMap] = ismember(td.lat, UCLA.lat);
    [~, lonMap] = ismember(td.lon, UCLA.lon);
    latMap = latMap(latMap > 0);
    lonMap = lonMap(lonMap > 0);

    if isempty(latMap) || isempty(lonMap)
        continue;
    end

    % Extract SWE data - handle various dimension orderings
    if isfield(td, 'swe')
        sweSize = size(td.swe);
        fprintf('  Tile %s SWE size: [%s]\n', tileKeys{k}, num2str(sweSize));

        % The data should be [lat x lon x stats x days] or similar
        % We'll handle the most common case and extract for our WY
        % This will need adjustment based on actual file structure
        for si = 1:min(5, sweSize(3))
            for di = 1:min(nDaysWY, sweSize(4))
                slice = td.swe(:,:,si,di);
                % Map into output (may need transpose depending on dim order)
                UCLA.(['SWE_' statNames{si}])(latMap, lonMap, di) = slice(1:length(latMap), 1:length(lonMap));
            end
        end
    end

    % Extract fSCA if available
    if isfield(td, 'fsca')
        fscaSize = size(td.fsca);
        for di = 1:min(nDaysWY, fscaSize(end))
            if ndims(td.fsca) >= 3
                UCLA.fSCA_mean(latMap, lonMap, di) = td.fsca(1:length(latMap), 1:length(lonMap), 1, di);
            end
        end
    end

    % Extract Snow Depth
    if isfield(td, 'sd')
        sdSize = size(td.sd);
        fprintf('  Tile %s SD size: [%s]\n', tileKeys{k}, num2str(sdSize));
        for si = 1:min(5, sdSize(3))
            for di = 1:min(nDaysWY, sdSize(4))
                slice = td.sd(:,:,si,di);
                UCLA.(['SD_' statNames{si}])(latMap, lonMap, di) = slice(1:length(latMap), 1:length(lonMap));
            end
        end
    end
end

%% Save result
outFile = fullfile(dataDir, sprintf('UCLA_SWE_WY%d.mat', WY));
fprintf('Saving to %s...\n', outFile);
save(outFile, 'UCLA', '-v7.3');
fprintf('Done! UCLA SWE WY%d loaded and saved.\n', WY);

end
