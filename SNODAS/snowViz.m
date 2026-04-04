%% snowViz.m - Interactive Snow Data Visualization Driver
%
% Main script for visualizing SNODAS and UCLA SWE snow products.
% Provides a menu-driven interface to:
%   1. Select data source (SNODAS or UCLA SWE)
%   2. Choose variable to visualize
%   3. Plot a single date OR generate a water year movie (MP4)
%
% PREREQUISITES:
%   - Downloaded data via getSNODAS_WY.m or getUCLA_SWE.m
%   - OR existing .mat files (SNODAS_WY####.mat, UCLA_SWE_WY####.mat)
%   - Mapping Toolbox (for usamap, geoshow, etc.)
%
% USAGE:
%   >> snowViz       % Run and follow the prompts
%
% HP Marshall, Boise State University
% SnowFusion Project
%
% See also: getSNODAS_WY, getUCLA_SWE, plotSnowVar, makeSnowMovie

clear; clc;

%% ========== CONFIGURATION ==========
% Default region: Boise River Basin
defaultBB = [-116.2 -114.6 43.2 44.4];
defaultShapefile = 'BRB_outline.shp'; % set to '' if not available

%% ========== STEP 1: Select Data Source ==========
fprintf('\n========================================\n');
fprintf('   SnowFusion Visualization Tool\n');
fprintf('========================================\n\n');
fprintf('Data Sources:\n');
fprintf('  [1] SNODAS (NOAA Snow Data Assimilation System)\n');
fprintf('      Variables: SWE, Depth, Precip, SnowPrecip, Tsnow, Melt,\n');
fprintf('                 Sublimation, SublimationBS\n\n');
fprintf('  [2] UCLA SWE (Western US Snow Reanalysis)\n');
fprintf('      Variables: SWE_mean, SWE_median, SWE_std, SWE_p25, SWE_p75,\n');
fprintf('                 fSCA_mean, SD_mean, SD_median, SD_std\n\n');
source = input('Select data source [1 or 2]: ');

%% ========== STEP 2: Load Data ==========
if source == 1
    %% SNODAS
    srcName = 'SNODAS';
    varList = {'SWE','Depth','Precip','SnowPrecip','Tsnow','Melt','Sublimation','SublimationBS'};

    % Check for existing .mat files (both naming conventions)
    matFiles = [dir('SNODAS_WY*.mat'); dir('data_BRB/SNODAS_BRB_WY*.mat')];
    if ~isempty(matFiles)
        fprintf('\nFound existing SNODAS files:\n');
        for f = 1:length(matFiles)
            fprintf('  [%d] %s\n', f, matFiles(f).name);
        end
        fprintf('  [0] Download new water year\n');
        choice = input('Select file to load [number]: ');
        if choice > 0
            loadPath = fullfile(matFiles(choice).folder, matFiles(choice).name);
            fprintf('Loading %s...\n', loadPath);
            tmp = load(loadPath);
            data = tmp.Snodas;
        else
            WY = input('Enter water year to download (e.g. 2020): ');
            BB = input(sprintf('Bounding box [lonmin lonmax latmin latmax]\n  (Enter for BRB default [%g %g %g %g]): ', defaultBB));
            if isempty(BB), BB = defaultBB; end
            data = getSNODAS_WY(WY, BB);
        end
    else
        fprintf('\nNo existing SNODAS .mat files found.\n');
        WY = input('Enter water year to download (e.g. 2020): ');
        BB = input(sprintf('Bounding box [lonmin lonmax latmin latmax]\n  (Enter for BRB default): '));
        if isempty(BB), BB = defaultBB; end
        data = getSNODAS_WY(WY, BB);
    end

elseif source == 2
    %% UCLA SWE
    srcName = 'UCLA SWE';
    varList = {'SWE_mean','SWE_median','SWE_std','SWE_p25','SWE_p75', ...
               'fSCA_mean','SD_mean','SD_median','SD_std'};

    matFiles = dir('UCLA_SWE_WY*.mat');
    if ~isempty(matFiles)
        fprintf('\nFound existing UCLA SWE files:\n');
        for f = 1:length(matFiles)
            fprintf('  [%d] %s\n', f, matFiles(f).name);
        end
        fprintf('  [0] Load new water year from NetCDF tiles\n');
        choice = input('Select file to load [number]: ');
        if choice > 0
            fprintf('Loading %s...\n', matFiles(choice).name);
            tmp = load(matFiles(choice).name);
            data = tmp.UCLA;
        else
            WY = input('Enter water year (1985-2021): ');
            BB = input(sprintf('Bounding box [lonmin lonmax latmin latmax]\n  (Enter for BRB default): '));
            if isempty(BB), BB = defaultBB; end
            dataDir = input('Path to UCLA NetCDF files: ', 's');
            data = getUCLA_SWE(WY, BB, dataDir);
        end
    else
        fprintf('\nNo existing UCLA SWE .mat files found.\n');
        WY = input('Enter water year (1985-2021): ');
        BB = input(sprintf('Bounding box [lonmin lonmax latmin latmax]\n  (Enter for BRB default): '));
        if isempty(BB), BB = defaultBB; end
        dataDir = input('Path to UCLA NetCDF files: ', 's');
        data = getUCLA_SWE(WY, BB, dataDir);
    end
else
    error('Invalid source selection. Choose 1 or 2.');
end

%% ========== STEP 3: Select Variable ==========
fprintf('\n--- Available Variables for %s ---\n', srcName);
% Only show variables that exist in the loaded data
availVars = {};
for v = 1:length(varList)
    if isfield(data, varList{v})
        availVars{end+1} = varList{v};
    end
end

for v = 1:length(availVars)
    fprintf('  [%d] %s\n', v, availVars{v});
end
varChoice = input('Select variable [number]: ');
selectedVar = availVars{varChoice};
fprintf('Selected: %s\n', selectedVar);

%% ========== STEP 4: Choose Mode ==========
fprintf('\n--- Visualization Mode ---\n');
fprintf('  [1] Single date figure\n');
fprintf('  [2] Water year movie (MP4)\n');
fprintf('  [3] Both\n');
mode = input('Select mode [1, 2, or 3]: ');

%% ========== STEP 5: Execute ==========

% Common options
plotOpts = {};
if exist(defaultShapefile, 'file')
    plotOpts = [plotOpts, 'shapefile', defaultShapefile];
end

% --- Single Date Figure ---
if mode == 1 || mode == 3
    fprintf('\nDate range: %s to %s\n', ...
        datestr(data.dates(1), 'yyyy-mm-dd'), ...
        datestr(data.dates(end), 'yyyy-mm-dd'));
    dateInput = input('Enter date (yyyy-mm-dd): ', 's');

    fprintf('Generating figure...\n');
    [hFig, ~] = plotSnowVar(data, selectedVar, datenum(dateInput, 'yyyy-mm-dd'), ...
        plotOpts{:});

    % Offer to save
    saveChoice = input('Save figure? [y/n]: ', 's');
    if strcmpi(saveChoice, 'y')
        outName = sprintf('%s_%s_%s.png', srcName, selectedVar, dateInput);
        outName = strrep(outName, ' ', '_');
        print(hFig, outName, '-dpng', '-r200');
        fprintf('Saved: %s\n', outName);
    end
end

% --- Water Year Movie ---
if mode == 2 || mode == 3
    % Movie parameters
    fps = input('Frames per second (default 10): ');
    if isempty(fps), fps = 10; end

    skipDays = input('Skip days (1=every day, 2=every other, etc. default 1): ');
    if isempty(skipDays), skipDays = 1; end

    movieFile = sprintf('%s_%s_WY%d.mp4', srcName, selectedVar, data.WY);
    movieFile = strrep(movieFile, ' ', '_');
    fprintf('Output: %s\n', movieFile);

    fprintf('Generating movie...\n');
    makeSnowMovie(data, selectedVar, movieFile, ...
        'fps', fps, ...
        'skipDays', skipDays, ...
        plotOpts{:});

    fprintf('\nMovie complete: %s\n', movieFile);
end

fprintf('\n========================================\n');
fprintf('   Done! SnowFusion Visualization\n');
fprintf('========================================\n');
