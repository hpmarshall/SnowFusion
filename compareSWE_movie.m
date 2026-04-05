% compareSWE_movie.m
% Side-by-side movie comparing SNODAS and UCLA SR SWE for WY2021
%
% Left panel:  SNODAS SWE
% Right panel: UCLA Snow Reanalysis SWE (ensemble mean)
%
% Both panels share the same spatial extent, color scale, date, and
% static overlays (BRB outline, SNOTEL sites).
%
% REQUIRES:
%   - SNODAS_BRB_WY2021.mat  (from getSNODAS_BRB.m)
%   - UCLA SR NetCDF tiles    (from getUCLA_SR_BRB.m)
%   - BRB_outline.shp
%   - Mapping Toolbox
%
% HP Marshall, Boise State University
% SnowFusion Project, April 2026

clear; clc; close all;

%% ====== CONFIGURATION ======
dataRoot  = '/Users/hpmarshall/DATA_DRIVE/SnowFusion';
scriptDir = fileparts(mfilename('fullpath'));

WY      = 2021;
wyStr   = 'WY2020_21';          % UCLA tile filename string
wyStart = datenum(WY-1, 10, 1); % Oct 1, 2020

% UCLA tile coverage
latTiles = [43 44];
lonTiles = [115 116 117];

% Movie settings
fps      = 10;
skipDays = 2;   % render every other day

% Spatial extent (matches UCLA tile coverage)
latlim = [43.0 45.0];
lonlim = [-117.0 -114.0];

% Shared SWE color limits [m]
climSWE = [0 1.5];

% Output
moviesDir = fullfile(dataRoot, 'Movies');
if ~exist(moviesDir, 'dir'), mkdir(moviesDir); end
movieFile = fullfile(moviesDir, sprintf('SWE_comparison_SNODAS_UCLA_WY%d.mp4', WY));

%% ====== LOAD SNODAS ======
fprintf('Loading SNODAS WY%d...\n', WY);
tmp = load(fullfile(dataRoot, 'SNODAS', sprintf('SNODAS_BRB_WY%d.mat', WY)), 'Snodas');
Snodas = tmp.Snodas;

snodas_lat = Snodas.lat;
snodas_lon = Snodas.lon;
snodas_SWE = Snodas.SWE;

% SNODAS lat is north-to-south — flip to south-to-north
if snodas_lat(1) > snodas_lat(end)
    snodas_lat = flip(snodas_lat);
    snodas_SWE = flip(snodas_SWE, 1);
end
[snodas_LON, snodas_LAT] = meshgrid(snodas_lon, snodas_lat);
fprintf('  SNODAS grid: %d lat x %d lon, %d days\n', ...
    length(snodas_lat), length(snodas_lon), length(Snodas.dates));

%% ====== LOAD UCLA SR ======
fprintf('Loading UCLA SR tiles (%s)...\n', wyStr);
[ucla_lat, ucla_lon, ucla_SWE_4d, ~, ~] = ...
    mosaicUCLA_SR(fullfile(dataRoot, 'UCLA_SR'), wyStr, latTiles, lonTiles);

% Extract ensemble mean (dim 3, index 1) -> [lat x lon x nDays]
ucla_SWE = squeeze(ucla_SWE_4d(:, :, 1, :));
[ucla_LON, ucla_LAT] = meshgrid(ucla_lon, ucla_lat);
nDaysUCLA    = size(ucla_SWE, 3);
uclaDateNums = wyStart + (0:nDaysUCLA-1);
fprintf('  UCLA grid: %d lat x %d lon, %d days\n', ...
    length(ucla_lat), length(ucla_lon), nDaysUCLA);

%% ====== ALIGN DATES ======
commonDates = intersect(Snodas.dates, uclaDateNums);
plotDates   = commonDates(1:skipDays:end);
nFrames     = length(plotDates);
fprintf('Common dates: %d  |  Frames to render: %d\n', ...
    length(commonDates), nFrames);

%% ====== LOAD STATIC OVERLAYS (once) ======
proj = projcrs(26911);  % NAD83 / UTM Zone 11N

% BRB shapefile
shpLat = [];  shpLon = [];
shpFile = fullfile(scriptDir, 'BRB_outline.shp');
if exist(shpFile, 'file')
    [ShpData, ~] = shaperead(shpFile);
    if max(ShpData.X) > 360   % UTM coordinates
        [shpLat, shpLon] = projinv(proj, ShpData.X, ShpData.Y);
    else
        shpLat = ShpData.Y;
        shpLon = ShpData.X;
    end
end

% SNOTEL sites
snotelShp = fullfile(scriptDir, 'SNOTEL/IDDCO_2020_automated_sites.shp');
snotel = getSNOTEL_BRB(snotelShp, latlim, lonlim);
fprintf('SNOTEL sites in region: %d\n', snotel.nStations);

%% ====== SET UP FIGURE AND VIDEO ======
hFig = figure('Color', 'w', 'Position', [50 50 1920 720]);

writerObj = VideoWriter(movieFile, 'MPEG-4');
writerObj.FrameRate = fps;
writerObj.Quality   = 90;
open(writerObj);

%% ====== FRAME LOOP ======
fprintf('Rendering frames...\n');
tic;
for fi = 1:nFrames
    d = plotDates(fi);

    % Find per-dataset day indices
    si = find(Snodas.dates   == d, 1);
    ui = find(uclaDateNums   == d, 1);

    % Extract SWE maps
    S_sn = snodas_SWE(:, :, si);          % SNODAS  [m]
    S_uc = ucla_SWE(:, :, ui);            % UCLA    [m]

    % Alpha masks: transparent where 0 or NaN
    A_sn = double(S_sn ~= 0 & ~isnan(S_sn));
    A_uc = double(S_uc ~= 0 & ~isnan(S_uc));

    dateStr = datestr(d, 'dd-mmm-yyyy');

    clf(hFig);

    %% ---- Left panel: SNODAS ----
    subplot(1, 2, 1);
    hAx1 = usamap(latlim, lonlim);
    hG = geoshow(snodas_LAT, snodas_LON, S_sn, 'DisplayType', 'texturemap');
    set(hG, 'FaceColor', 'texturemap', 'CData', S_sn, ...
            'EdgeColor', 'none', 'FaceAlpha', 'texture', 'AlphaData', A_sn);
    colormap(hAx1, parula);
    caxis(climSWE);
    set(hAx1, 'Color', 'w');
    setm(hAx1, 'FFaceColor', 'w');

    if ~isempty(shpLat)
        hold on;
        plot3m(shpLat, shpLon, 100*ones(size(shpLat)), ...
            'Color', [0.2 0.2 0.2], 'LineWidth', 2);
    end
    if snotel.nStations > 0
        hold on;
        plot3m(snotel.lat, snotel.lon, 100*ones(size(snotel.lat)), ...
            'rp', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
    end

    hC = colorbar('Location', 'southoutside');
    ylabel(hC, 'SWE [m]', 'FontSize', 11, 'FontWeight', 'bold');
    setm(hAx1, 'FontSize', 11, 'FontWeight', 'bold');
    title(sprintf('SNODAS SWE\n%s', dateStr), 'FontSize', 13, 'FontWeight', 'bold');

    %% ---- Right panel: UCLA SR ----
    subplot(1, 2, 2);
    hAx2 = usamap(latlim, lonlim);
    hG = geoshow(ucla_LAT, ucla_LON, S_uc, 'DisplayType', 'texturemap');
    set(hG, 'FaceColor', 'texturemap', 'CData', S_uc, ...
            'EdgeColor', 'none', 'FaceAlpha', 'texture', 'AlphaData', A_uc);
    colormap(hAx2, parula);
    caxis(climSWE);
    set(hAx2, 'Color', 'w');
    setm(hAx2, 'FFaceColor', 'w');

    if ~isempty(shpLat)
        hold on;
        plot3m(shpLat, shpLon, 100*ones(size(shpLat)), ...
            'Color', [0.2 0.2 0.2], 'LineWidth', 2);
    end
    if snotel.nStations > 0
        hold on;
        plot3m(snotel.lat, snotel.lon, 100*ones(size(snotel.lat)), ...
            'rp', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
    end

    hC = colorbar('Location', 'southoutside');
    ylabel(hC, 'SWE [m]', 'FontSize', 11, 'FontWeight', 'bold');
    setm(hAx2, 'FontSize', 11, 'FontWeight', 'bold');
    title(sprintf('UCLA SR SWE (ensemble mean)\n%s', dateStr), ...
        'FontSize', 13, 'FontWeight', 'bold');

    %% ---- Shared title and frame capture ----
    sgtitle(sprintf('SWE Comparison  —  WY%d', WY), ...
        'FontSize', 15, 'FontWeight', 'bold');

    drawnow;
    writeVideo(writerObj, getframe(hFig));

    if mod(fi, 50) == 0
        fprintf('  %d / %d frames\n', fi, nFrames);
    end
end
elapsed = toc;
fprintf('Done: %d frames in %.1f sec (%.1f fps render)\n', ...
    nFrames, elapsed, nFrames/elapsed);

close(writerObj);
close(hFig);
fprintf('Movie saved: %s\n', movieFile);
