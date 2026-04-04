function [lat, lon, SWE, fSCA, SD] = mosaicUCLA_SR(dataDir, wyStr, latTiles, lonTiles)
% mosaicUCLA_SR - Read and mosaic WUS UCLA Snow Reanalysis tiles
%
% Reads multiple 1-deg x 1-deg NetCDF tiles and mosaics them into a
% continuous grid covering the region of interest.
%
% INPUTS:
%   dataDir  - directory containing downloaded .nc files
%   wyStr    - water year string, e.g. 'WY2020_21'
%   latTiles - vector of tile lower-left latitudes, e.g. [43 44]
%   lonTiles - vector of tile lower-left west longitudes, e.g. [115 116 117]
%
% OUTPUTS:
%   lat   - [M x 1] latitude vector (degrees N, descending)
%   lon   - [1 x N] longitude vector (degrees E, ascending)
%   SWE   - [M x N x 5 x nDays] snow water equivalent [m]
%   fSCA  - [M x N x 5 x nDays] fractional snow-covered area [0-1]
%   SD    - [M x N x 5 x nDays] snow depth [m]
%
% Ensemble stats dimension (dim 3):
%   1=mean, 2=std, 3=25th pctl, 4=50th pctl (median), 5=75th pctl
%
% HP Marshall, Boise State University, April 2026

nLat = length(latTiles);
nLon = length(lonTiles);

%% First pass: read one file to get dimensions and variable names
testTile = sprintf('N%d_0W%d_0', latTiles(1), lonTiles(1));
testFiles = dir(fullfile(dataDir, sprintf('*%s*%s*.nc', testTile, wyStr)));

if isempty(testFiles)
    % Try without water year filter
    testFiles = dir(fullfile(dataDir, sprintf('*%s*.nc', testTile)));
end

if isempty(testFiles)
    error('No NetCDF files found for tile %s in %s', testTile, dataDir);
end

testFile = fullfile(dataDir, testFiles(1).name);
info = ncinfo(testFile);

% Discover variable names (they may vary between versions)
varNames = {info.Variables.Name};
fprintf('Variables in NetCDF: %s\n', strjoin(varNames, ', '));

% Find coordinate variables
latVarName = findVar(varNames, {'lat', 'Latitude', 'latitude', 'y'});
lonVarName = findVar(varNames, {'lon', 'Longitude', 'longitude', 'x'});
sweVarName = findVar(varNames, {'SWE', 'swe', 'snow_water_equivalent'});
fscaVarName = findVar(varNames, {'fSCA', 'fsca', 'SCA', 'snow_cover', 'fractional_snow_covered_area'});
sdVarName = findVar(varNames, {'SD', 'sd', 'snow_depth', 'Depth', 'depth'});

fprintf('Using variables: lat=%s, lon=%s, SWE=%s, fSCA=%s, SD=%s\n', ...
    latVarName, lonVarName, sweVarName, fscaVarName, sdVarName);

% Read test tile to get per-tile dimensions
testLat = ncread(testFile, latVarName);
testLon = ncread(testFile, lonVarName);
testSWE = ncread(testFile, sweVarName);
tileSize = size(testSWE);
nLatPix = length(testLat);    % typically 225
nLonPix = length(testLon);    % typically 225
nEns    = tileSize(3);        % typically 5
nDays   = tileSize(4);        % typically 366 (or 365)

fprintf('Tile dimensions: %d lat x %d lon x %d ensemble x %d days\n', ...
    nLatPix, nLonPix, nEns, nDays);

%% Allocate output arrays
totalLatPix = nLatPix * nLat;
totalLonPix = nLonPix * nLon;

SWE  = NaN(totalLonPix, totalLatPix, nEns, nDays);
fSCA = NaN(totalLonPix, totalLatPix, nEns, nDays);
SD   = NaN(totalLonPix, totalLatPix, nEns, nDays);
latAll = NaN(totalLatPix, 1);
lonAll = NaN(totalLonPix, 1);

%% Read and mosaic all tiles
for iLat = 1:nLat
    for iLon = 1:nLon
        tileStr = sprintf('N%d_0W%d_0', latTiles(iLat), lonTiles(iLon));
        tileFiles = dir(fullfile(dataDir, sprintf('*%s*%s*.nc', tileStr, wyStr)));

        if isempty(tileFiles)
            tileFiles = dir(fullfile(dataDir, sprintf('*%s*.nc', tileStr)));
        end

        if isempty(tileFiles)
            fprintf('  WARNING: No file found for tile %s, filling with NaN\n', tileStr);
            continue;
        end

        fname = fullfile(dataDir, tileFiles(1).name);
        fprintf('  Reading: %s\n', tileFiles(1).name);

        % Read coordinates
        tileLat = ncread(fname, latVarName);
        tileLon = ncread(fname, lonVarName);

        % Read data variables
        tileSWE  = ncread(fname, sweVarName);
        tilefSCA = ncread(fname, fscaVarName);
        tileSD   = ncread(fname, sdVarName);

        % Calculate position in mosaic
        % Latitude: tiles ordered south to north (latTiles ascending)
        latStart = (iLat - 1) * nLatPix + 1;
        latEnd   = iLat * nLatPix;

        % Longitude: tiles ordered east to west (lonTiles = west longitude, ascending)
        % So W117 is westernmost, W115 is easternmost
        % Reverse: iLon=1 (smallest W value) goes to rightmost position
        lonIdx = nLon - iLon + 1; % reverse so W117 is leftmost
        lonStart = (lonIdx - 1) * nLonPix + 1;
        lonEnd   = lonIdx * nLonPix;

        % Store data
        SWE(lonStart:lonEnd, latStart:latEnd, :, :)  = tileSWE;
        fSCA(lonStart:lonEnd, latStart:latEnd, :, :) = tilefSCA;
        SD(lonStart:lonEnd, latStart:latEnd, :, :)   = tileSD;

        % Store coordinates
        latAll(latStart:latEnd) = tileLat;
        lonAll(lonStart:lonEnd) = tileLon;
    end
end

%% Sort and reshape output
% NetCDF convention: ncread returns data as [lon x lat x ens x time]
% We want output as [lat x lon x ens x time] with lat descending (north to south)

% Sort latitude descending (north to south for imagesc)
[latAll, latSortIdx] = sort(latAll, 'descend');
% Sort longitude ascending (west to east)
[lonAll, lonSortIdx] = sort(lonAll, 'ascend');

% Permute from [lon x lat x ens x time] to [lat x lon x ens x time]
SWE  = permute(SWE, [2 1 3 4]);
fSCA = permute(fSCA, [2 1 3 4]);
SD   = permute(SD, [2 1 3 4]);

% Apply coordinate sorting
SWE  = SWE(latSortIdx, lonSortIdx, :, :);
fSCA = fSCA(latSortIdx, lonSortIdx, :, :);
SD   = SD(latSortIdx, lonSortIdx, :, :);

lat = latAll;
lon = lonAll';

fprintf('Mosaic complete: %d x %d pixels\n', length(lat), length(lon));

end

%% ====== Helper function ======
function vname = findVar(varNames, candidates)
% Find the first matching variable name from a list of candidates
    vname = '';
    for i = 1:length(candidates)
        idx = find(strcmpi(varNames, candidates{i}), 1);
        if ~isempty(idx)
            vname = varNames{idx};
            return;
        end
    end
    % If no exact match, try partial matching
    for i = 1:length(candidates)
        idx = find(contains(lower(varNames), lower(candidates{i})), 1);
        if ~isempty(idx)
            vname = varNames{idx};
            return;
        end
    end
    warning('Could not find variable matching: %s', strjoin(candidates, ', '));
    vname = candidates{1}; % fallback to first candidate
end
