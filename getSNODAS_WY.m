function Snodas = getSNODAS_WY(WY, BB, outDir)
% getSNODAS_WY - Download SNODAS data for a water year and bounding box
%
% USAGE:
%   Snodas = getSNODAS_WY(WY, BB, outDir)
%
% INPUTS:
%   WY    - Water year (e.g. 2020 = Oct 2019 - Sep 2020)
%   BB    - Bounding box [lonmin lonmax latmin latmax]
%           Default: Boise River Basin [-116.2 -114.6 43.2 44.4]
%   outDir - Output directory for saving .mat files (default: current dir)
%
% OUTPUT:
%   Snodas - Structure with fields:
%       .WY        - Water year
%       .lat       - latitude vector
%       .lon       - longitude vector
%       .dates     - datenum vector of dates
%       .datestr   - cell array of date strings
%       .SWE       - Snow Water Equivalent [m]      (ny x nx x ndays)
%       .Depth     - Snow Depth [m]                  (ny x nx x ndays)
%       .Precip    - Precipitation [m]               (ny x nx x ndays)
%       .SnowPrecip- Snow Precipitation [m WE]       (ny x nx x ndays)
%       .Tsnow     - Snow Temperature [K]            (ny x nx x ndays)
%       .Melt      - Snowmelt [m]                    (ny x nx x ndays)
%       .Sublimation    - Pack Sublimation [m]       (ny x nx x ndays)
%       .SublimationBS  - Blowing Snow Sublim [m]    (ny x nx x ndays)
%
% EXAMPLE:
%   % Download WY2020 for Boise River Basin
%   BB = [-116.2 -114.6 43.2 44.4];
%   Snodas = getSNODAS_WY(2020, BB);
%
% HP Marshall, Boise State University
% SnowFusion Project

if nargin < 2 || isempty(BB)
    BB = [-116.2 -114.6 43.2 44.4]; % Boise River Basin
end
if nargin < 3 || isempty(outDir)
    outDir = '/Users/hpmarshall/DATA_DRIVE/SnowFusion/SNODAS';
    if ~exist(outDir, 'dir'); mkdir(outDir); end
end

%% Set up SNODAS grid
lonmin = -124.733749999999;
lonmax = -66.9420833333342;
latmin = 24.9495833333335;
latmax = 52.8745833333323;
lon = linspace(lonmin, lonmax, 6935);
lat = linspace(latmax, latmin, 3351);

% Get indices for bounding box
Ix = find(lon > BB(1) & lon < BB(2));
Iy = find(lat > BB(3) & lat < BB(4));

% Store coordinate vectors
Snodas.WY = WY;
Snodas.lat = lat(Iy);
Snodas.lon = lon(Ix);
nx = length(Ix);
ny = length(Iy);

%% Product codes and names
Scodes = {'1025SlL00','1025SlL01','1034','1036','1038','1039','1044','1050'};
Snames = {'Precip','SnowPrecip','SWE','Depth','Tsnow','SublimationBS','Melt','Sublimation'};
% Scale factors to convert to standard units
% Precip/SnowPrecip: stored as kg/m^2 * 10 -> divide by 10 to get mm
% SWE/Depth: stored as m * 1000 -> divide by 1000 to get m
% Tsnow: stored as K (no scaling needed, factor = 1)
% Sublimation/Melt: stored as m * 100000 -> divide by 100000 to get m
Sscale = [1/10, 1/10, 1/1000, 1/1000, 1, 1/100000, 1/100000, 1/100000];

%% Build list of dates for the water year (Oct 1 through Sep 30)
startDate = datenum(WY-1, 10, 1);
endDate   = datenum(WY, 9, 30);
allDates  = startDate:endDate;
nDays     = length(allDates);

% Pre-allocate
for v = 1:length(Snames)
    Snodas.(Snames{v}) = NaN(ny, nx, nDays);
end
Snodas.dates   = allDates;
Snodas.datestr = cellstr(datestr(allDates, 'yyyy-mm-dd'));

%% Connect to SNODAS FTP
fprintf('Connecting to SNODAS FTP server...\n');
mw = ftp('sidads.colorado.edu', 'anonymous', 'snowfusion@boisestate.edu');
basePath = '/DATASETS/NOAA/G02158/masked/';

% Create temp directory for downloads
tmpDir = fullfile(outDir, 'SNODAS_tmp');
if ~exist(tmpDir, 'dir'), mkdir(tmpDir); end
origDir = pwd;
cd(tmpDir);

%% Loop over each day
fprintf('Downloading SNODAS for WY%d (%d days)...\n', WY, nDays);
for d = 1:nDays
    dv = datevec(allDates(d));
    yr = dv(1); mo = dv(2); dy = dv(3);

    % Build remote path
    moStr = sprintf('%02d_%s', mo, datestr(allDates(d), 'mmm'));
    remotePath = sprintf('%s%d/%s/', basePath, yr, moStr);

    % Find the tar file for this date
    tarName = sprintf('SNODAS_%d%02d%02d.tar', yr, mo, dy);

    try
        cd(mw, remotePath);
        d3 = dir(mw, '*.tar');
        tarFiles = {d3.name};

        % Find matching tar file
        matchIdx = find(contains(tarFiles, sprintf('%d%02d%02d', yr, mo, dy)));
        if isempty(matchIdx)
            fprintf('  [%s] No data found, skipping.\n', Snodas.datestr{d});
            continue;
        end

        % Download and extract
        mget(mw, d3(matchIdx(1)).name);
        untar(d3(matchIdx(1)).name);

        % Read each variable
        for v = 1:length(Scodes)
            Dt = dir(['*' Scodes{v} '*.dat.gz']);
            if ~isempty(Dt)
                gunzip(Dt(1).name);
                delete(Dt(1).name);
                Dt = dir(['*' Scodes{v} '*.dat']);
                fid = fopen(Dt(1).name);
                D3 = fread(fid, [6935 3351], 'int16', 'b');
                D3 = D3';
                Snodas.(Snames{v})(:,:,d) = D3(Iy, Ix) * Sscale(v);
                fclose(fid);
                delete(Dt(1).name);
            end
        end

        % Clean up
        delete(d3(matchIdx(1)).name);
        dfiles = dir('*.gz');
        for f = 1:length(dfiles), delete(dfiles(f).name); end
        dfiles = dir('*.dat');
        for f = 1:length(dfiles), delete(dfiles(f).name); end
        dfiles = dir('*.Hdr');
        for f = 1:length(dfiles), delete(dfiles(f).name); end
        dfiles = dir('*.txt');
        for f = 1:length(dfiles), delete(dfiles(f).name); end

        if mod(d, 30) == 0
            fprintf('  [%s] %d/%d days complete.\n', Snodas.datestr{d}, d, nDays);
        end

    catch ME
        fprintf('  [%s] Error: %s, skipping.\n', Snodas.datestr{d}, ME.message);
    end
end

%% Save result
cd(origDir);
outFile = fullfile(outDir, sprintf('SNODAS_WY%d.mat', WY));
fprintf('Saving to %s...\n', outFile);
save(outFile, 'Snodas', '-v7.3');
fprintf('Done! SNODAS WY%d downloaded and saved.\n', WY);

% Clean up temp
try
    rmdir(tmpDir, 's');
catch
end

close(mw);
end
