function [lat, lon, SWE, fSCA, SD] = mosaicUCLA_SR(dataDir, wyStr, latTiles, lonTiles)
% mosaicUCLA_SR - Read and mosaic WUS UCLA Snow Reanalysis tiles
%
% Reads multiple 1-deg x 1-deg NetCDF tiles and mosaics them into a
% continuous grid covering the region of interest.
%
% NOTE: The UCLA SR dataset uses separate files for different variables:
%   *_SWE_SCA_POST.nc -> contains SWE_Post and SCA_Post
%   *_SD_POST.nc      -> contains SD_Post
%
% NetCDF dimension ordering (from ncread):
%   [225 x 225 x 5 x 366] = [Latitude x Longitude x ensemble x day]
%   - dim1 corresponds to Latitude
%   - dim2 corresponds to Longitude
%   So ncread returns [lat x lon x ens x day] — NO permute needed.
%
% This function uses coordinate-based placement: each tile's lat/lon
% arrays are read and matched to the mosaic grid, avoiding any
% assumptions about tile ordering.
%
% INPUTS:
%   dataDir  - directory containing downloaded .nc files
%   wyStr    - water year string, e.g. 'WY2020_21'
%   latTiles - vector of tile lower-left latitudes, e.g. [43 44]
%   lonTiles - vector of tile lower-left west longitudes, e.g. [115 116 117]
%
% OUTPUTS:
%   lat   - [M x 1] latitude vector (degrees N, descending = north to south)
%   lon   - [1 x N] longitude vector (degrees E, ascending = west to east)
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

%% Read first tile to discover variable names and get dimensions
testTile = sprintf('N%d_0W%d_0', latTiles(1), lonTiles(1));
sweFiles = dir(fullfile(dataDir, sprintf('*%s*%s*SWE_SCA_POST*.nc', testTile, wyStr)));
if isempty(sweFiles)
    sweFiles = dir(fullfile(dataDir, sprintf('*%s*SWE_SCA_POST*.nc', testTile)));
end
sdFiles = dir(fullfile(dataDir, sprintf('*%s*%s*SD_POST*.nc', testTile, wyStr)));
if isempty(sdFiles)
    sdFiles = dir(fullfile(dataDir, sprintf('*%s*SD_POST*.nc', testTile)));
end

hasSWE = ~isempty(sweFiles);
hasSD  = ~isempty(sdFiles);

if ~hasSWE && ~hasSD
    error('No NetCDF files found for tile %s in %s\nRun getUCLA_SR_BRB.m first.', testTile, dataDir);
end

%% Discover variable names
if hasSWE
    testFile = fullfile(dataDir, sweFiles(1).name);
    info = ncinfo(testFile);
    varNames = {info.Variables.Name};
    fprintf('SWE/SCA file: %s\n', sweFiles(1).name);
    fprintf('  Variables: %s\n', strjoin(varNames, ', '));
    sweVarName  = findVar(varNames, {'SWE_Post', 'SWE', 'swe'});
    fscaVarName = findVar(varNames, {'SCA_Post', 'fSCA', 'fsca', 'SCA'});
else
    testFile = fullfile(dataDir, sdFiles(1).name);
    info = ncinfo(testFile);
    varNames = {info.Variables.Name};
    fprintf('SD file: %s\n', sdFiles(1).name);
    fprintf('  Variables: %s\n', strjoin(varNames, ', '));
end

latVarName = findVar(varNames, {'Latitude', 'lat', 'latitude'});
lonVarName = findVar(varNames, {'Longitude', 'lon', 'longitude'});

if hasSD
    sdTestFile = fullfile(dataDir, sdFiles(1).name);
    sdInfo = ncinfo(sdTestFile);
    sdVarNames = {sdInfo.Variables.Name};
    fprintf('SD file: %s\n', sdFiles(1).name);
    fprintf('  Variables: %s\n', strjoin(sdVarNames, ', '));
    sdVarName    = findVar(sdVarNames, {'SD_Post', 'SD', 'sd', 'snow_depth'});
    sdLatVarName = findVar(sdVarNames, {'Latitude', 'lat', 'latitude'});
    sdLonVarName = findVar(sdVarNames, {'Longitude', 'lon', 'longitude'});
end

% Get per-tile dimensions from test data
if hasSWE
    testData = ncread(testFile, sweVarName);
else
    testData = ncread(testFile, sdVarName);
end
% ncread returns [lat(225) x lon(225) x ensemble(5) x day(365/366)]
nEns  = size(testData, 3);
nDays = size(testData, 4);

testLat = ncread(testFile, latVarName);
testLon = ncread(testFile, lonVarName);
nLatPix = length(testLat);
nLonPix = length(testLon);

fprintf('Per-tile: %d lon x %d lat x %d ensemble x %d days\n', ...
    nLonPix, nLatPix, nEns, nDays);
if hasSWE; fprintf('SWE var: %s, SCA var: %s\n', sweVarName, fscaVarName); end
if hasSD;  fprintf('SD var:  %s\n', sdVarName); end

%% Build the full mosaic coordinate vectors
% Collect all coordinates from all tiles, then sort into a single grid.
allLats = [];
allLons = [];

for iLat = 1:nLat
    for iLon = 1:nLon
        tileStr = sprintf('N%d_0W%d_0', latTiles(iLat), lonTiles(iLon));
        if hasSWE
            f = dir(fullfile(dataDir, sprintf('*%s*%s*SWE_SCA_POST*.nc', tileStr, wyStr)));
            if isempty(f); f = dir(fullfile(dataDir, sprintf('*%s*SWE_SCA_POST*.nc', tileStr))); end
        else
            f = dir(fullfile(dataDir, sprintf('*%s*%s*SD_POST*.nc', tileStr, wyStr)));
            if isempty(f); f = dir(fullfile(dataDir, sprintf('*%s*SD_POST*.nc', tileStr))); end
        end
        if isempty(f); continue; end

        tileLat = ncread(fullfile(dataDir, f(1).name), latVarName);
        tileLon = ncread(fullfile(dataDir, f(1).name), lonVarName);
        allLats = [allLats; tileLat(:)]; %#ok<AGROW>
        allLons = [allLons; tileLon(:)]; %#ok<AGROW>
    end
end

% Latitude descending (north to south) for natural imagesc display
latVec = sort(unique(allLats), 'descend');
% Longitude ascending (west to east)
lonVec = sort(unique(allLons), 'ascend');

totalLatPix = length(latVec);
totalLonPix = length(lonVec);
fprintf('Mosaic grid: %d lat x %d lon pixels\n', totalLatPix, totalLonPix);

%% Allocate output: [lat x lon x ensemble x day]
SWE  = NaN(totalLatPix, totalLonPix, nEns, nDays);
fSCA = NaN(totalLatPix, totalLonPix, nEns, nDays);
SD   = NaN(totalLatPix, totalLonPix, nEns, nDays);

%% Read and place each tile using coordinate-based indexing
tol = 1e-6; % tolerance for coordinate matching

for iLat = 1:nLat
    for iLon = 1:nLon
        tileStr = sprintf('N%d_0W%d_0', latTiles(iLat), lonTiles(iLon));

        %% SWE and SCA from SWE_SCA_POST file
        if hasSWE
            sweF = dir(fullfile(dataDir, sprintf('*%s*%s*SWE_SCA_POST*.nc', tileStr, wyStr)));
            if isempty(sweF)
                sweF = dir(fullfile(dataDir, sprintf('*%s*SWE_SCA_POST*.nc', tileStr)));
            end
            if ~isempty(sweF)
                fname = fullfile(dataDir, sweF(1).name);
                fprintf('  Reading SWE/SCA: %s\n', sweF(1).name);

                tileLat = ncread(fname, latVarName);
                tileLon = ncread(fname, lonVarName);

                % ncread returns [lat x lon x ens x day] — no permute needed
                tileSWE  = ncread(fname, sweVarName);
                tilefSCA = ncread(fname, fscaVarName);

                % Map tile coordinates to mosaic indices
                latIdx = findCoordIdx(tileLat, latVec, tol);
                lonIdx = findCoordIdx(tileLon, lonVec, tol);

                SWE(latIdx, lonIdx, :, :)  = tileSWE;
                fSCA(latIdx, lonIdx, :, :) = tilefSCA;
            else
                fprintf('  WARNING: No SWE_SCA file for tile %s\n', tileStr);
            end
        end

        %% SD from SD_POST file
        if hasSD
            sdF = dir(fullfile(dataDir, sprintf('*%s*%s*SD_POST*.nc', tileStr, wyStr)));
            if isempty(sdF)
                sdF = dir(fullfile(dataDir, sprintf('*%s*SD_POST*.nc', tileStr)));
            end
            if ~isempty(sdF)
                fname = fullfile(dataDir, sdF(1).name);
                fprintf('  Reading SD:      %s\n', sdF(1).name);

                tileLat = ncread(fname, sdLatVarName);
                tileLon = ncread(fname, sdLonVarName);
                tileSD  = ncread(fname, sdVarName);

                latIdx = findCoordIdx(tileLat, latVec, tol);
                lonIdx = findCoordIdx(tileLon, lonVec, tol);

                SD(latIdx, lonIdx, :, :) = tileSD;
            else
                fprintf('  WARNING: No SD file for tile %s\n', tileStr);
            end
        end
    end
end

lat = latVec;
lon = lonVec';

fprintf('Mosaic complete: %d x %d pixels\n', length(lat), length(lon));

end

%% ====== Helper: find variable name ======
function vname = findVar(varNames, candidates)
    vname = '';
    for i = 1:length(candidates)
        idx = find(strcmpi(varNames, candidates{i}), 1);
        if ~isempty(idx)
            vname = varNames{idx};
            return;
        end
    end
    for i = 1:length(candidates)
        idx = find(contains(lower(varNames), lower(candidates{i})), 1);
        if ~isempty(idx)
            vname = varNames{idx};
            return;
        end
    end
    warning('Could not find variable matching: %s', strjoin(candidates, ', '));
    vname = candidates{1};
end

%% ====== Helper: map tile coordinates to mosaic indices ======
function idx = findCoordIdx(tileCoords, mosaicCoords, tol)
% For each coordinate in tileCoords, find its index in mosaicCoords.
% Returns an index vector the same length as tileCoords.
    idx = NaN(length(tileCoords), 1);
    for i = 1:length(tileCoords)
        d = abs(mosaicCoords - tileCoords(i));
        [minD, minI] = min(d);
        if minD < tol
            idx(i) = minI;
        else
            error('Coordinate %.6f not found in mosaic grid (nearest: %.6f, dist: %.6f)', ...
                tileCoords(i), mosaicCoords(minI), minD);
        end
    end
end
