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
% REQUIRES:
%   1) NASA Earthdata Login: https://urs.earthdata.nasa.gov
%   2) Python 3 with earthaccess: pip install earthaccess
%   3) Authorize "NSIDC_DATAPOOL_OPS" app in Earthdata profile
%
% NOTE: This dataset has migrated to NASA Earthdata Cloud. The old
% daacdata.apps.nsidc.org and n5eil01u.ecs.nsidc.org URLs no longer work.
% We use Python's earthaccess library which handles all URL discovery and
% OAuth2 authentication automatically.
%
% HP Marshall, Boise State University
% Created: April 2026

clear; clc;

%% ====== USER CONFIGURATION ======
% Earthdata Login credentials
% Loaded from local credentials file (listed in .gitignore)
credFile = fullfile(fileparts(mfilename('fullpath')), 'earthdata_credentials.m');
if exist(credFile, 'file')
    run(credFile);
    fprintf('Loaded credentials from earthdata_credentials.m\n');
else
    error(['Earthdata credentials not found. Create earthdata_credentials.m with:\n' ...
           '  earthdata_user = ''your_username'';\n' ...
           '  earthdata_pass = ''your_password'';\n']);
end

% Water year to download (dataset covers WY1985 to WY2021)
water_year_start = 2020;  % WY2021 = Oct 2020 - Sep 2021
water_year_end   = 21;    % 2-digit end year

% Output directory (external data drive - keeps large files out of git repo)
dataRoot = '/Users/hpmarshall/DATA_DRIVE/SnowFusion';
outDir = fullfile(dataRoot, 'UCLA_SR');
if ~exist(outDir, 'dir'); mkdir(outDir); end

%% ====== DETERMINE TILES COVERING BOISE RIVER BASIN ======
% BRB approximate extent: lat [43.0 44.5], lon [-116.3 -114.3]
% Tiles are 1 deg x 1 deg, named by lower-left corner
latTiles = [43 44];          % lower-left latitude of each tile
lonTiles = [115 116 117];    % lower-left west longitude of each tile

wyStr = sprintf('WY%d_%02d', water_year_start, water_year_end);
nTiles = length(latTiles) * length(lonTiles);
fprintf('\n=== WUS UCLA Snow Reanalysis Downloader ===\n');
fprintf('Water Year: %s\n', wyStr);
fprintf('Tiles needed: %d (lat: %s, lon: %s)\n', nTiles, ...
    mat2str(latTiles), mat2str(lonTiles));
fprintf('Output: %s\n\n', outDir);

%% ====== BUILD EXPECTED FILENAMES ======
% The dataset uses separate files for different variables:
%   *_SWE_SCA_POST.nc -> contains SWE_Post and SCA_Post (SWE + fractional snow cover)
%   *_SD_POST.nc      -> contains SD_Post (snow depth)
tileNames = {};
tileStrs = {};
for iLat = 1:length(latTiles)
    for iLon = 1:length(lonTiles)
        tStr = sprintf('N%d_0W%d_0', latTiles(iLat), lonTiles(iLon));
        tileStrs{end+1} = tStr; %#ok<SAGROW>
        % SWE/SCA file
        tileNames{end+1} = sprintf('WUS_UCLA_SR_v01_%s_agg_16_%s_SWE_SCA_POST.nc', tStr, wyStr); %#ok<SAGROW>
        % SD file
        tileNames{end+1} = sprintf('WUS_UCLA_SR_v01_%s_agg_16_%s_SD_POST.nc', tStr, wyStr); %#ok<SAGROW>
    end
end
nExpectedFiles = length(tileNames);  % both SWE_SCA and SD for each tile

%% ====== CHECK ALREADY DOWNLOADED FILES ======
existCount = 0;
for iTile = 1:length(tileNames)
    outFile = fullfile(outDir, tileNames{iTile});
    if exist(outFile, 'file')
        finfo = dir(outFile);
        if finfo.bytes > 1e6
            fprintf('  Already have: %s (%.1f MB)\n', tileNames{iTile}, finfo.bytes/1e6);
            existCount = existCount + 1;
        end
    end
end

if existCount >= nExpectedFiles
    fprintf('\nAll %d files already downloaded. Skipping download.\n', nExpectedFiles);
else
    fprintf('\nHave %d of %d files. Need to download %d more.\n', ...
        existCount, nExpectedFiles, nExpectedFiles - existCount);

    %% ====== DOWNLOAD USING PYTHON EARTHACCESS ======
    % earthaccess handles all URL discovery and OAuth2 auth automatically.
    % This is the most reliable method since NSIDC migrated to Earthdata Cloud.

    fprintf('\n--- Downloading via Python earthaccess ---\n');

    % Verify Python and earthaccess are available
    [pyStatus, pyVer] = system('python3 --version 2>&1');
    if pyStatus ~= 0
        [pyStatus, pyVer] = system('python --version 2>&1');
        if pyStatus ~= 0
            error('Python 3 not found. Please install Python 3 and earthaccess: pip install earthaccess');
        end
        pythonCmd = 'python';
    else
        pythonCmd = 'python3';
    end
    fprintf('Using: %s\n', strtrim(pyVer));

    % Check earthaccess is installed
    [eaStatus, ~] = system(sprintf('%s -c "import earthaccess; print(earthaccess.__version__)" 2>&1', pythonCmd));
    if eaStatus ~= 0
        error(['earthaccess not installed. Install with:\n' ...
               '  pip install earthaccess\n' ...
               'Then restart MATLAB from the same terminal.']);
    end

    % Build and write the Python download script
    pyScript = fullfile(tempdir, 'download_ucla_sr.py');
    fid = fopen(pyScript, 'w');

    fprintf(fid, '#!/usr/bin/env python3\n');
    fprintf(fid, '"""Download WUS UCLA SR tiles using earthaccess."""\n');
    fprintf(fid, 'import os, sys, json\n');
    fprintf(fid, 'import earthaccess\n');
    fprintf(fid, '\n');
    fprintf(fid, '# Configuration\n');
    fprintf(fid, 'os.environ["EARTHDATA_USERNAME"] = "%s"\n', earthdata_user);
    fprintf(fid, 'os.environ["EARTHDATA_PASSWORD"] = "%s"\n', earthdata_pass);
    fprintf(fid, 'OUT_DIR = "%s"\n', strrep(outDir, '\', '/'));
    fprintf(fid, 'WY_STR = "%s"\n', wyStr);
    fprintf(fid, '\n');
    fprintf(fid, '# Tile identifiers we need (BRB region)\n');
    fprintf(fid, 'TILE_IDS = %s\n', python_list(tileStrs));
    fprintf(fid, '\n');
    fprintf(fid, 'print("Logging into Earthdata...")\n');
    fprintf(fid, 'try:\n');
    fprintf(fid, '    auth = earthaccess.login(strategy="environment")\n');
    fprintf(fid, '    if not auth.authenticated:\n');
    fprintf(fid, '        print("ERROR:AUTH_FAILED")\n');
    fprintf(fid, '        sys.exit(1)\n');
    fprintf(fid, '    print("  Authenticated successfully.")\n');
    fprintf(fid, 'except Exception as e:\n');
    fprintf(fid, '    print(f"ERROR:AUTH_EXCEPTION:{e}")\n');
    fprintf(fid, '    sys.exit(1)\n');
    fprintf(fid, '\n');
    fprintf(fid, '# Search for all WUS_UCLA_SR granules in the BRB bounding box\n');
    fprintf(fid, 'print("\\nSearching for WUS_UCLA_SR granules...")\n');
    fprintf(fid, 'try:\n');
    fprintf(fid, '    results = earthaccess.search_data(\n');
    fprintf(fid, '        short_name="WUS_UCLA_SR",\n');
    fprintf(fid, '        bounding_box=(-117, 43, -114, 45),\n');
    fprintf(fid, '        count=2000\n');
    fprintf(fid, '    )\n');
    fprintf(fid, '    print(f"  Found {len(results)} granules total.")\n');
    fprintf(fid, 'except Exception as e:\n');
    fprintf(fid, '    print(f"ERROR:SEARCH_FAILED:{e}")\n');
    fprintf(fid, '    sys.exit(1)\n');
    fprintf(fid, '\n');
    fprintf(fid, 'if len(results) == 0:\n');
    fprintf(fid, '    print("ERROR:NO_RESULTS")\n');
    fprintf(fid, '    print("  The dataset may not be indexed in CMR, or the search parameters need adjustment.")\n');
    fprintf(fid, '    print("  Try searching without bounding_box...")\n');
    fprintf(fid, '    try:\n');
    fprintf(fid, '        results = earthaccess.search_data(\n');
    fprintf(fid, '            short_name="WUS_UCLA_SR",\n');
    fprintf(fid, '            count=2000\n');
    fprintf(fid, '        )\n');
    fprintf(fid, '        print(f"  Found {len(results)} granules total (no bbox filter).")\n');
    fprintf(fid, '    except Exception as e:\n');
    fprintf(fid, '        print(f"ERROR:SEARCH2_FAILED:{e}")\n');
    fprintf(fid, '        sys.exit(1)\n');
    fprintf(fid, '\n');
    fprintf(fid, 'if len(results) == 0:\n');
    fprintf(fid, '    print("ERROR:STILL_NO_RESULTS")\n');
    fprintf(fid, '    print("  No granules found even without spatial filter.")\n');
    fprintf(fid, '    print("  The dataset may need to be accessed differently.")\n');
    fprintf(fid, '    # Print collection-level info for debugging\n');
    fprintf(fid, '    try:\n');
    fprintf(fid, '        collections = earthaccess.search_datasets(short_name="WUS_UCLA_SR")\n');
    fprintf(fid, '        print(f"  Collections found: {len(collections)}")\n');
    fprintf(fid, '        for c in collections:\n');
    fprintf(fid, '            print(f"    - {c[''meta''][''concept-id'']}: {c[''umm''][''ShortName'']} v{c[''umm''].get(''Version'',''?'')}")\n');
    fprintf(fid, '            # Check for direct distribution info\n');
    fprintf(fid, '            dist = c[''umm''].get(''RelatedUrls'', [])\n');
    fprintf(fid, '            for d in dist[:5]:\n');
    fprintf(fid, '                print(f"      URL: {d.get(''URL'',''?'')} ({d.get(''Type'',''?'')})")\n');
    fprintf(fid, '    except Exception as e2:\n');
    fprintf(fid, '        print(f"  Could not query collections: {e2}")\n');
    fprintf(fid, '    sys.exit(1)\n');
    fprintf(fid, '\n');
    fprintf(fid, '# Show what we found and filter for our water year + tiles\n');
    fprintf(fid, 'print(f"\\nFiltering for {WY_STR} and BRB tiles...")\n');
    fprintf(fid, 'to_download = []\n');
    fprintf(fid, 'matched_files = []\n');
    fprintf(fid, '\n');
    fprintf(fid, 'for r in results:\n');
    fprintf(fid, '    try:\n');
    fprintf(fid, '        # Get all data links (external = HTTPS, not S3)\n');
    fprintf(fid, '        links = r.data_links(access="external")\n');
    fprintf(fid, '        if not links:\n');
    fprintf(fid, '            links = r.data_links()  # try any access type\n');
    fprintf(fid, '        for link in links:\n');
    fprintf(fid, '            fn = link.split("/")[-1]\n');
    fprintf(fid, '            # Check if this file matches our water year\n');
    fprintf(fid, '            if WY_STR not in fn:\n');
    fprintf(fid, '                continue\n');
    fprintf(fid, '            # Check if this file matches any of our needed tiles\n');
    fprintf(fid, '            for tile_id in TILE_IDS:\n');
    fprintf(fid, '                if tile_id in fn and fn.endswith(".nc"):\n');
    fprintf(fid, '                    outpath = os.path.join(OUT_DIR, fn)\n');
    fprintf(fid, '                    if os.path.exists(outpath) and os.path.getsize(outpath) > 1e6:\n');
    fprintf(fid, '                        print(f"  SKIP (exists): {fn}")\n');
    fprintf(fid, '                    else:\n');
    fprintf(fid, '                        print(f"  QUEUE: {fn}")\n');
    fprintf(fid, '                        print(f"    URL: {link}")\n');
    fprintf(fid, '                        to_download.append(r)\n');
    fprintf(fid, '                        matched_files.append(fn)\n');
    fprintf(fid, '                    break\n');
    fprintf(fid, '    except Exception as e:\n');
    fprintf(fid, '        print(f"  Warning: Could not process granule: {e}")\n');
    fprintf(fid, '\n');
    fprintf(fid, 'print(f"\\nQueued {len(to_download)} tiles for download.")\n');
    fprintf(fid, '\n');
    fprintf(fid, 'if to_download:\n');
    fprintf(fid, '    print(f"\\nDownloading to: {OUT_DIR}")\n');
    fprintf(fid, '    try:\n');
    fprintf(fid, '        downloaded = earthaccess.download(to_download, OUT_DIR)\n');
    fprintf(fid, '        print(f"\\nDownloaded {len(downloaded)} file(s):")\n');
    fprintf(fid, '        for f in downloaded:\n');
    fprintf(fid, '            sz = os.path.getsize(str(f)) / 1e6 if os.path.exists(str(f)) else 0\n');
    fprintf(fid, '            print(f"  DOWNLOADED:{f} ({sz:.1f} MB)")\n');
    fprintf(fid, '    except Exception as e:\n');
    fprintf(fid, '        print(f"ERROR:DOWNLOAD_FAILED:{e}")\n');
    fprintf(fid, '        sys.exit(1)\n');
    fprintf(fid, 'else:\n');
    fprintf(fid, '    if matched_files:\n');
    fprintf(fid, '        print("All matched files already exist.")\n');
    fprintf(fid, '    else:\n');
    fprintf(fid, '        print("WARNING: No files matched our tile/WY criteria.")\n');
    fprintf(fid, '        print("Listing first 10 granule filenames found for debugging:")\n');
    fprintf(fid, '        for i, r in enumerate(results[:10]):\n');
    fprintf(fid, '            try:\n');
    fprintf(fid, '                links = r.data_links(access="external")\n');
    fprintf(fid, '                if not links:\n');
    fprintf(fid, '                    links = r.data_links()\n');
    fprintf(fid, '                for link in links:\n');
    fprintf(fid, '                    fn = link.split("/")[-1]\n');
    fprintf(fid, '                    if fn.endswith(".nc"):\n');
    fprintf(fid, '                        print(f"  [{i}] {fn}")\n');
    fprintf(fid, '                        print(f"       {link}")\n');
    fprintf(fid, '            except:\n');
    fprintf(fid, '                pass\n');
    fprintf(fid, '\n');
    fprintf(fid, 'print("\\nDONE")\n');

    fclose(fid);

    % Run the Python script and capture output
    fprintf('Running Python download script...\n\n');
    [pyStatus, pyOutput] = system(sprintf('%s "%s" 2>&1', pythonCmd, pyScript));
    fprintf('%s\n', pyOutput);

    % Parse results
    if contains(pyOutput, 'ERROR:AUTH_FAILED') || contains(pyOutput, 'ERROR:AUTH_EXCEPTION')
        fprintf('\n*** AUTHENTICATION FAILED ***\n');
        fprintf('Check your credentials in earthdata_credentials.m\n');
        fprintf('Also verify at: https://urs.earthdata.nasa.gov\n');
    elseif contains(pyOutput, 'ERROR:SEARCH_FAILED')
        fprintf('\n*** SEARCH FAILED ***\n');
        fprintf('earthaccess could not search for granules.\n');
    elseif contains(pyOutput, 'STILL_NO_RESULTS')
        fprintf('\n*** NO GRANULES FOUND ***\n');
        fprintf('The dataset may not have granule-level CMR entries.\n');
        fprintf('See collection info above for alternative access URLs.\n');
    end

    % Clean up
    if exist(pyScript, 'file'); delete(pyScript); end
end

%% ====== VERIFY DOWNLOADS ======
% Check for files with either naming convention
ncFiles = dir(fullfile(outDir, '*SWE_SCA_POST*.nc'));
fprintf('\n=== Download Summary ===\n');
fprintf('NetCDF files in %s:\n', outDir);
validCount = 0;
for i = 1:length(ncFiles)
    if ncFiles(i).bytes > 1e6
        fprintf('  %s (%.1f MB)\n', ncFiles(i).name, ncFiles(i).bytes/1e6);
        validCount = validCount + 1;
    else
        fprintf('  %s (%.0f bytes - INVALID)\n', ncFiles(i).name, ncFiles(i).bytes);
    end
end
fprintf('Valid NetCDF files: %d\n', validCount);

% Quick peek at first valid file structure
if validCount > 0
    for i = 1:length(ncFiles)
        if ncFiles(i).bytes > 1e6
            testFile = fullfile(outDir, ncFiles(i).name);
            fprintf('\n=== NetCDF File Structure ===\n');
            info = ncinfo(testFile);
            fprintf('File: %s\n', ncFiles(i).name);
            fprintf('Variables:\n');
            for j = 1:length(info.Variables)
                v = info.Variables(j);
                dimStr = strjoin(arrayfun(@(d) sprintf('%s=%d', d.Name, d.Length), ...
                    v.Dimensions, 'UniformOutput', false), ' x ');
                fprintf('  %s [%s]\n', v.Name, dimStr);
            end
            break;
        end
    end
end

if validCount == 0
    fprintf('\n============================================\n');
    fprintf('AUTOMATED DOWNLOAD COULD NOT FIND FILES\n');
    fprintf('============================================\n');
    fprintf('Please download manually:\n');
    fprintf('  1. Go to: https://nsidc.org/data/data-access-tool/WUS_UCLA_SR/versions/1\n');
    fprintf('  2. Set bounding box to: lat [43, 45], lon [-117, -114]\n');
    fprintf('  3. Select water year: %s\n', wyStr);
    fprintf('  4. Download the .nc files to: %s\n', outDir);
    fprintf('  5. Then run plotUCLA_SR_BRB.m to visualize\n');
    fprintf('============================================\n');
end

fprintf('\nDone! Now run plotUCLA_SR_BRB.m to visualize.\n');

%% ====== HELPER FUNCTION ======
function s = python_list(cellArr)
    % Convert MATLAB cell array of strings to Python list literal
    items = cellfun(@(x) sprintf('"%s"', x), cellArr, 'UniformOutput', false);
    s = ['[' strjoin(items, ', ') ']'];
end
