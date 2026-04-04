% getUCLA_SR_BRB.m
% Downloads WUS UCLA Snow Reanalysis (WUS_UCLA_SR v01) NetCDF tiles
% covering the Boise River Basin from NASA Earthdata Cloud (NSIDC DAAC).
%
% Dataset: https://nsidc.org/data/wus_ucla_sr/versions/1
% Resolution: 16 arc-second (~500 m), daily, WY1985-2021
% Variables: SWE, fSCA, snow depth (SD)
% Dimensions per tile: [225 x 225 x 5 x 366] = lat x lon x ensemble_stats x day_of_WY
%   ensemble_stats: 1=mean, 2=std, 3=25th pctl, 4=50th pctl (median), 5=75th pctl
%
% REQUIRES: NASA Earthdata Login account
%   1) Create account at: https://urs.earthdata.nasa.gov
%   2) Set your credentials below OR configure a ~/.netrc file
%
% HP Marshall, Boise State University
% Created: April 2026

clear; clc;

%% ====== USER CONFIGURATION ======
% Earthdata Login credentials
earthdata_user = 'YOUR_USERNAME';   % <-- Replace with your Earthdata username
earthdata_pass = 'YOUR_PASSWORD';   % <-- Replace with your Earthdata password

% Water year to download (dataset covers WY1985 to WY2021)
water_year_start = 2020;  % WY2021 = Oct 2020 - Sep 2021
water_year_end   = 21;    % 2-digit end year

% Output directory for downloaded files
outDir = fullfile(pwd, 'data');
if ~exist(outDir, 'dir'); mkdir(outDir); end

%% ====== DETERMINE TILES COVERING BOISE RIVER BASIN ======
% BRB approximate extent: lat [43.0 44.5], lon [-116.3 -114.3]
% Tiles are 1 deg x 1 deg, named by lower-left corner
% Latitude tiles needed: N43, N44
% Longitude tiles needed: W115, W116, W117 (note: W = positive west)

latTiles = [43 44];          % lower-left latitude of each tile
lonTiles = [115 116 117];    % lower-left west longitude of each tile

fprintf('=== WUS UCLA Snow Reanalysis Downloader ===\n');
fprintf('Water Year: WY%d_%02d\n', water_year_start, water_year_end);
fprintf('Tiles needed for Boise River Basin:\n');

%% ====== BUILD DOWNLOAD URLs AND FETCH FILES ======
% Base URL for NSIDC DAAC Earthdata Cloud
% The data lives at: https://data.nsidc.earthdatacloud.nasa.gov/
% Path pattern: /DATASETS/WUS_UCLA_SR/v01/
baseURL = 'https://n5eil01u.ecs.nsidc.org/DP5/DATASETS/WUS_UCLA_SR.001/';

% File naming convention from user guide:
% WUS_UCLA_SR_v01_N{lat}_0W{lon}_0_agg_16_WY{startyr}_{endyr}_SWE_SCA_POST.nc
wyStr = sprintf('WY%d_%02d', water_year_start, water_year_end);

% Set up web options with Earthdata authentication
opts = weboptions('Username', earthdata_user, ...
                  'Password', earthdata_pass, ...
                  'Timeout', 300, ...
                  'CertificateFilename', '');

% Try alternative URL patterns (NSIDC has moved data between servers)
baseURLs = { ...
    ['https://n5eil01u.ecs.nsidc.org/DP5/WUS_UCLA_SR.001/' wyStr '/'], ...
    ['https://daacdata.apps.nsidc.org/pub/DATASETS/WUS_UCLA_SR/v01/' wyStr '/'], ...
    ['https://data.nsidc.earthdatacloud.nasa.gov/DATASETS/WUS_UCLA_SR/v01/' wyStr '/'] ...
};

downloadedFiles = {};
nFile = 0;

for iLat = 1:length(latTiles)
    for iLon = 1:length(lonTiles)
        tileStr = sprintf('N%d_0W%d_0', latTiles(iLat), lonTiles(iLon));
        fname = sprintf('WUS_UCLA_SR_v01_%s_agg_16_%s_SWE_SCA_POST.nc', tileStr, wyStr);
        outFile = fullfile(outDir, fname);

        fprintf('  Tile: %s -> %s\n', tileStr, fname);

        if exist(outFile, 'file')
            fprintf('    Already exists, skipping download.\n');
            nFile = nFile + 1;
            downloadedFiles{nFile} = outFile; %#ok<SAGROW>
            continue;
        end

        downloaded = false;
        for iURL = 1:length(baseURLs)
            url = [baseURLs{iURL} fname];
            fprintf('    Trying: %s\n', baseURLs{iURL});
            try
                websave(outFile, url, opts);
                fprintf('    SUCCESS: Downloaded %s\n', fname);
                nFile = nFile + 1;
                downloadedFiles{nFile} = outFile; %#ok<SAGROW>
                downloaded = true;
                break;
            catch ME
                fprintf('    Failed: %s\n', ME.message);
            end
        end

        if ~downloaded
            fprintf('    WARNING: Could not download %s from any URL.\n', fname);
            fprintf('    Try downloading manually from:\n');
            fprintf('    https://nsidc.org/data/data-access-tool/WUS_UCLA_SR/versions/1\n');
        end
    end
end

%% ====== ALTERNATIVE: USE CMR API TO FIND EXACT GRANULE URLs ======
% If the direct URL patterns above don't work, use NASA's Common Metadata
% Repository (CMR) to search for granule download links.
%
% This section queries CMR for WUS_UCLA_SR granules within the BRB bounding
% box and extracts the HTTPS download URLs.

if nFile == 0
    fprintf('\n--- Attempting CMR API search for granule URLs ---\n');

    % CMR search parameters
    cmrURL = 'https://cmr.earthdata.nasa.gov/search/granules.json';
    shortName = 'WUS_UCLA_SR';
    version = '001';
    bbox = '-117,43,-114,45'; % W,S,E,N bounding box for BRB region

    searchURL = sprintf('%s?short_name=%s&version=%s&bounding_box=%s&page_size=20', ...
        cmrURL, shortName, version, bbox);

    try
        cmrOpts = weboptions('Timeout', 60, 'ContentType', 'json');
        result = webread(searchURL, cmrOpts);

        if isfield(result, 'feed') && isfield(result.feed, 'entry')
            entries = result.feed.entry;
            fprintf('Found %d granules in CMR.\n', length(entries));

            % Filter for our water year
            for iEntry = 1:length(entries)
                entry = entries(iEntry);
                entryTitle = entry.title;

                % Check if this granule matches our water year
                if contains(entryTitle, wyStr)
                    % Extract download URL from links
                    links = entry.links;
                    for iLink = 1:length(links)
                        if isfield(links(iLink), 'rel') && ...
                           contains(links(iLink).rel, 'data') && ...
                           endsWith(links(iLink).href, '.nc')

                            url = links(iLink).href;
                            [~, fnameFromURL, ext] = fileparts(url);
                            outFile = fullfile(outDir, [fnameFromURL ext]);

                            fprintf('  Downloading: %s\n', [fnameFromURL ext]);
                            try
                                websave(outFile, url, opts);
                                nFile = nFile + 1;
                                downloadedFiles{nFile} = outFile; %#ok<SAGROW>
                                fprintf('    SUCCESS\n');
                            catch ME
                                fprintf('    FAILED: %s\n', ME.message);
                            end
                        end
                    end
                end
            end
        end
    catch ME
        fprintf('CMR search failed: %s\n', ME.message);
    end
end

%% ====== ALTERNATIVE: MANUAL DOWNLOAD INSTRUCTIONS ======
if nFile == 0
    fprintf('\n============================================\n');
    fprintf('MANUAL DOWNLOAD INSTRUCTIONS:\n');
    fprintf('============================================\n');
    fprintf('1. Go to: https://nsidc.org/data/data-access-tool/WUS_UCLA_SR/versions/1\n');
    fprintf('2. Set bounding box to: lat [43, 45], lon [-117, -114]\n');
    fprintf('3. Select water year: WY%d_%02d\n', water_year_start, water_year_end);
    fprintf('4. Download the .nc files to: %s\n', outDir);
    fprintf('5. Then run plotUCLA_SR_BRB.m to visualize\n');
    fprintf('============================================\n');
end

%% ====== VERIFY DOWNLOADS ======
ncFiles = dir(fullfile(outDir, '*.nc'));
fprintf('\n=== Download Summary ===\n');
fprintf('NetCDF files in %s: %d\n', outDir, length(ncFiles));
for i = 1:length(ncFiles)
    fprintf('  %s (%.1f MB)\n', ncFiles(i).name, ncFiles(i).bytes/1e6);
end

% Quick peek at first file structure
if ~isempty(ncFiles)
    testFile = fullfile(outDir, ncFiles(1).name);
    fprintf('\n=== NetCDF File Structure ===\n');
    info = ncinfo(testFile);
    fprintf('File: %s\n', ncFiles(1).name);
    fprintf('Variables:\n');
    for i = 1:length(info.Variables)
        v = info.Variables(i);
        dimStr = strjoin(arrayfun(@(d) sprintf('%s=%d', d.Name, d.Length), ...
            v.Dimensions, 'UniformOutput', false), ' x ');
        fprintf('  %s [%s]\n', v.Name, dimStr);
    end
end

fprintf('\nDone! Now run plotUCLA_SR_BRB.m to visualize.\n');
