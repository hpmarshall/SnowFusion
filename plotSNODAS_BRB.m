% plotSNODAS_BRB.m
% Visualize SNODAS data over the Boise River Basin
%
% Reads downloaded SNODAS .mat file, clips to BRB shapefile,
% and creates maps of SWE, Snow Depth, Melt, plus time series.
%
% Generates 6 figures (mirroring plotUCLA_SR_BRB.m):
%   1. SWE map for target date
%   2. Snow Depth map for target date
%   3. Daily Melt map for target date
%   4. 3-panel summary (SWE, Depth, Melt)
%   5. Time series of basin-mean SWE over water year
%   6. SWE vs Snow Depth scatter / density relationship
%
% REQUIRES:
%   - SNODAS_BRB_WY####.mat file (from getSNODAS_BRB.m)
%   - BRB_outline.shp (with .dbf, .shx, .prj companion files)
%   - Mapping Toolbox (for UTM conversion and map display)
%
% HP Marshall, Boise State University
% SnowFusion Project
% Created: April 2026

clear; clc; close all;

%% ====== CONFIGURATION ======
dataRoot = '/Users/hpmarshall/DATA_DRIVE/SnowFusion';
dataDir = fullfile(dataRoot, 'SNODAS');      % directory with .mat files
scriptDir = fileparts(mfilename('fullpath'));
shpFile = fullfile(scriptDir, 'BRB_outline.shp');  % BRB shapefile (UTM Zone 11N)
WY      = 2021;                              % Water year

% Date of interest (standard: April 1 for peak SWE assessment)
targetDate = datenum(WY, 4, 1);

% Coordinate system: true = UTM Zone 11N [km], false = geographic [deg]
useUTM = true;

%% ====== LOAD DATA ======
matFile = fullfile(dataDir, sprintf('SNODAS_BRB_WY%d.mat', WY));
if ~exist(matFile, 'file')
    error('Data file not found: %s\nRun getSNODAS_BRB.m first.', matFile);
end

fprintf('Loading %s...\n', matFile);
load(matFile, 'Snodas');

lat = Snodas.lat;
lon = Snodas.lon;
fprintf('Grid size: %d lat x %d lon\n', length(lat), length(lon));

%% ====== LOAD AND CONVERT BRB SHAPEFILE ======
proj = projcrs(26911);  % NAD83 / UTM Zone 11N

fprintf('Loading BRB shapefile...\n');
if exist(shpFile, 'file')
    [S, A] = shaperead(shpFile);

    % Shapefile is in NAD83 UTM Zone 11N - convert to geographic coordinates
    [S_lat, S_lon] = projinv(proj, S.X, S.Y);

    % Remove NaN boundary markers for polygon operations
    validIdx = ~isnan(S_lat) & ~isnan(S_lon);

    fprintf('BRB extent: lat [%.2f, %.2f], lon [%.2f, %.2f]\n', ...
        min(S_lat(validIdx)), max(S_lat(validIdx)), ...
        min(S_lon(validIdx)), max(S_lon(validIdx)));

    hasShapefile = true;
else
    fprintf('WARNING: BRB shapefile not found. Plotting without basin outline.\n');
    hasShapefile = false;
end

%% ====== HANDLE LATITUDE ORIENTATION ======
% SNODAS lat is north-to-south. For imagesc with 'YDir','normal' we need
% lat ascending (south-to-north). Flip if needed.
if lat(1) > lat(end)
    lat = flip(lat);
    % Flip all data along lat dimension (dim 1)
    varNames = {'SWE','Depth','Precip','SnowPrecip','Tsnow','SublimationBS','Melt','Sublimation'};
    for vi = 1:length(varNames)
        if isfield(Snodas, varNames{vi})
            Snodas.(varNames{vi}) = flip(Snodas.(varNames{vi}), 1);
        end
    end
    Snodas.lat = lat;
    fprintf('Flipped latitude to ascending (south-to-north) for plotting.\n');
end

%% ====== CREATE MASK FOR BRB ======
[LON, LAT] = meshgrid(lon, lat);

if hasShapefile
    inBRB = inpolygon(LON, LAT, S_lon, S_lat);
    fprintf('Pixels inside BRB: %d of %d (%.1f%%)\n', ...
        sum(inBRB(:)), numel(inBRB), 100*sum(inBRB(:))/numel(inBRB));
else
    % Use all pixels if no shapefile
    inBRB = true(size(LON));
end

%% ====== LOAD SNOTEL SITES ======
% Filter to the data grid extent (all sites visible in the plotted region)
snotelShp = fullfile(scriptDir, 'SNOTEL/IDDCO_2020_automated_sites.shp');
snotel = getSNOTEL_BRB(snotelShp, [min(lat) max(lat)], [min(lon) max(lon)]);
fprintf('Loaded %d SNOTEL stations within plotted region\n', snotel.nStations);

%% ====== SET UP PLOTTING COORDINATES ======
if useUTM
    % Convert data grid to UTM (km)
    [E_grid, N_grid] = projfwd(proj, LAT, LON);
    plot_x = E_grid(1,:) / 1000;
    plot_y = N_grid(:,1) / 1000;

    % Shapefile: use native UTM coordinates
    if hasShapefile
        plot_shp_x = S.X / 1000;
        plot_shp_y = S.Y / 1000;
    end

    % SNOTEL to UTM
    [snotel_e, snotel_n] = projfwd(proj, snotel.lat, snotel.lon);
    plot_snotel_x = snotel_e / 1000;
    plot_snotel_y = snotel_n / 1000;

    xLabel = 'Easting [km]';
    yLabel = 'Northing [km]';
    fprintf('Using UTM Zone 11N coordinates [km]\n');
else
    plot_x = lon;
    plot_y = lat;
    if hasShapefile
        plot_shp_x = S_lon;
        plot_shp_y = S_lat;
    end
    plot_snotel_x = snotel.lon;
    plot_snotel_y = snotel.lat;
    xLabel = 'Longitude [deg]';
    yLabel = 'Latitude [deg]';
    fprintf('Using geographic coordinates [deg]\n');
end

%% ====== EXTRACT DATA FOR TARGET DATE ======
[~, dayIdx] = min(abs(Snodas.dates - targetDate));
actualDate = Snodas.dates(dayIdx);
dateStr = datestr(actualDate, 'dd-mmm-yyyy');

fprintf('Target date: %s (day index %d)\n', dateStr, dayIdx);

% Extract maps for target date
SWE_map   = Snodas.SWE(:,:,dayIdx);       % [m]
Depth_map = Snodas.Depth(:,:,dayIdx);      % [m]
Melt_map  = Snodas.Melt(:,:,dayIdx);       % [m]

% Set zero values to NaN so they render transparent in all plots
SWE_map(SWE_map == 0)     = NaN;
Depth_map(Depth_map == 0) = NaN;
Melt_map(Melt_map == 0)   = NaN;

%% ====== FIGURE 1: SWE MAP ======
figure(1); clf;
set(gcf, 'Position', [50 50 900 700], 'Color', 'w');

h = imagesc(plot_x, plot_y, SWE_map * 100); % convert m to cm
set(h, 'AlphaData', ~isnan(SWE_map));
set(gca, 'YDir', 'normal');
hold on;
if hasShapefile
    plot(plot_shp_x, plot_shp_y, 'k-', 'LineWidth', 2);
end
plot(plot_snotel_x, plot_snotel_y, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
for si = 1:snotel.nStations
    text(plot_snotel_x(si), plot_snotel_y(si), ['  ' snotel.name{si}], ...
        'FontSize', 8, 'FontWeight', 'bold', 'Color', 'r');
end
hold off;

colorbar;
colormap(parula);
caxis([0 max(SWE_map(:)*100, [], 'omitnan')]);
set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel(xLabel);
ylabel(yLabel);
title(sprintf('SNODAS - SWE [cm] - %s\nBoise River Basin, WY%d', dateStr, WY), ...
    'FontSize', 16);
axis equal tight;
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SNODAS_SWE_WY%d_day%03d.png', WY, dayIdx)));

%% ====== FIGURE 2: SNOW DEPTH MAP ======
figure(2); clf;
set(gcf, 'Position', [100 50 900 700], 'Color', 'w');

h = imagesc(plot_x, plot_y, Depth_map * 100); % convert m to cm
set(h, 'AlphaData', ~isnan(Depth_map));
set(gca, 'YDir', 'normal');
hold on;
if hasShapefile
    plot(plot_shp_x, plot_shp_y, 'k-', 'LineWidth', 2);
end
plot(plot_snotel_x, plot_snotel_y, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
for si = 1:snotel.nStations
    text(plot_snotel_x(si), plot_snotel_y(si), ['  ' snotel.name{si}], ...
        'FontSize', 8, 'FontWeight', 'bold', 'Color', 'r');
end
hold off;

colorbar;
colormap(parula);
caxis([0 max(Depth_map(:)*100, [], 'omitnan')]);
set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel(xLabel);
ylabel(yLabel);
title(sprintf('SNODAS - Snow Depth [cm] - %s\nBoise River Basin, WY%d', dateStr, WY), ...
    'FontSize', 16);
axis equal tight;
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SNODAS_Depth_WY%d_day%03d.png', WY, dayIdx)));

%% ====== FIGURE 3: DAILY MELT MAP ======
figure(3); clf;
set(gcf, 'Position', [150 50 900 700], 'Color', 'w');

h = imagesc(plot_x, plot_y, Melt_map * 1000); % convert m to mm
set(h, 'AlphaData', ~isnan(Melt_map));
set(gca, 'YDir', 'normal');
hold on;
if hasShapefile
    plot(plot_shp_x, plot_shp_y, 'k-', 'LineWidth', 2);
end
plot(plot_snotel_x, plot_snotel_y, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
for si = 1:snotel.nStations
    text(plot_snotel_x(si), plot_snotel_y(si), ['  ' snotel.name{si}], ...
        'FontSize', 8, 'FontWeight', 'bold', 'Color', 'r');
end
hold off;

colorbar;
cmap_melt = [1 1 1; flipud(autumn(255))]; % white for 0, warm colors for melt
colormap(cmap_melt);
caxis([0 max(Melt_map(:)*1000, [], 'omitnan')]);
set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel(xLabel);
ylabel(yLabel);
title(sprintf('SNODAS - Daily Melt [mm] - %s\nBoise River Basin, WY%d', dateStr, WY), ...
    'FontSize', 16);
axis equal tight;
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SNODAS_Melt_WY%d_day%03d.png', WY, dayIdx)));

%% ====== FIGURE 4: 3-PANEL SUMMARY ======
figure(4); clf;
set(gcf, 'Position', [50 50 1600 500], 'Color', 'w');

subplot(1, 3, 1);
h = imagesc(plot_x, plot_y, SWE_map * 100);
set(h, 'AlphaData', ~isnan(SWE_map));
set(gca, 'YDir', 'normal', 'FontSize', 12, 'FontWeight', 'bold');
hold on;
if hasShapefile, plot(plot_shp_x, plot_shp_y, 'k-', 'LineWidth', 2); end
plot(plot_snotel_x, plot_snotel_y, 'rp', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
hold off;
colorbar; colormap(gca, parula);
title(sprintf('SWE [cm]\n%s', dateStr));
xlabel(xLabel); ylabel(yLabel); axis equal tight;

subplot(1, 3, 2);
h = imagesc(plot_x, plot_y, Depth_map * 100);
set(h, 'AlphaData', ~isnan(Depth_map));
set(gca, 'YDir', 'normal', 'FontSize', 12, 'FontWeight', 'bold');
hold on;
if hasShapefile, plot(plot_shp_x, plot_shp_y, 'k-', 'LineWidth', 2); end
plot(plot_snotel_x, plot_snotel_y, 'rp', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
hold off;
colorbar; colormap(gca, parula);
title(sprintf('Snow Depth [cm]\n%s', dateStr));
xlabel(xLabel); ylabel(yLabel); axis equal tight;

subplot(1, 3, 3);
h = imagesc(plot_x, plot_y, Melt_map * 1000);
set(h, 'AlphaData', ~isnan(Melt_map));
set(gca, 'YDir', 'normal', 'FontSize', 12, 'FontWeight', 'bold');
hold on;
if hasShapefile, plot(plot_shp_x, plot_shp_y, 'k-', 'LineWidth', 2); end
plot(plot_snotel_x, plot_snotel_y, 'rp', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
hold off;
colorbar;
cmap_melt3 = [1 1 1; flipud(autumn(255))];
colormap(gca, cmap_melt3);
title(sprintf('Daily Melt [mm]\n%s', dateStr));
xlabel(xLabel); ylabel(yLabel); axis equal tight;

sgtitle(sprintf('SNODAS - Boise River Basin - WY%d', WY), ...
    'FontSize', 16, 'FontWeight', 'bold');
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SNODAS_summary_WY%d_day%03d.png', WY, dayIdx)));

%% ====== FIGURE 5: TIME SERIES OF BASIN-MEAN SWE ======
figure(5); clf;
set(gcf, 'Position', [50 50 1000 400], 'Color', 'w');

% Compute basin-mean SWE and Depth for each day
nDays = length(Snodas.dates);
meanSWE   = NaN(nDays, 1);
meanDepth = NaN(nDays, 1);
meanMelt  = NaN(nDays, 1);

for d = 1:nDays
    sweDay = Snodas.SWE(:,:,d);
    sweDay(~inBRB) = NaN;
    meanSWE(d) = mean(sweDay(:), 'omitnan');

    depDay = Snodas.Depth(:,:,d);
    depDay(~inBRB) = NaN;
    meanDepth(d) = mean(depDay(:), 'omitnan');

    meltDay = Snodas.Melt(:,:,d);
    meltDay(~inBRB) = NaN;
    meanMelt(d) = mean(meltDay(:), 'omitnan');
end

% Convert to calendar dates
dates = datetime(Snodas.dates, 'ConvertFrom', 'datenum');

% Plot SWE and Depth on dual y-axes
yyaxis left;
plot(dates, meanSWE * 100, 'b-', 'LineWidth', 2);
ylabel('Basin Mean SWE [cm]');
set(gca, 'YColor', 'b');

yyaxis right;
plot(dates, meanDepth * 100, 'r-', 'LineWidth', 1.5);
ylabel('Basin Mean Depth [cm]');
set(gca, 'YColor', 'r');

hold on;
% Mark April 1
xline(datetime(WY, 4, 1), 'k--', 'Apr 1', 'LineWidth', 1.5, 'FontSize', 12);
hold off;

set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel('Date');
title(sprintf('Boise River Basin - SNODAS SWE & Depth - WY%d', WY), ...
    'FontSize', 14);
legend('SWE', 'Depth', 'Location', 'northwest');
grid on;
xlim([dates(1) dates(end)]);

print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SNODAS_SWE_timeseries_WY%d.png', WY)));

%% ====== FIGURE 6: SWE vs SNOW DEPTH RELATIONSHIP ======
% (SNODAS analog of UCLA's uncertainty map - shows SWE:Depth ratio/density)
figure(6); clf;
set(gcf, 'Position', [50 50 1000 800], 'Color', 'w');

% Subplot 1: Scatter of SWE vs Depth for target date
subplot(2, 1, 1);
swe_vals  = SWE_map(inBRB & ~isnan(SWE_map) & SWE_map > 0) * 100;   % cm
dep_vals  = Depth_map(inBRB & ~isnan(Depth_map) & Depth_map > 0) * 100; % cm

if ~isempty(swe_vals) && ~isempty(dep_vals)
    % Use only pixels where both are valid and positive
    validPx = SWE_map > 0 & Depth_map > 0 & inBRB & ~isnan(SWE_map) & ~isnan(Depth_map);
    swe_px = SWE_map(validPx) * 100;
    dep_px = Depth_map(validPx) * 100;

    scatter(dep_px, swe_px, 3, 'b', 'filled', 'MarkerFaceAlpha', 0.1);
    hold on;
    % Add 1:1 line and typical density lines
    maxVal = max([max(dep_px) max(swe_px)]);
    plot([0 maxVal], [0 maxVal * 0.30], 'r--', 'LineWidth', 1.5); % 30% density
    plot([0 maxVal], [0 maxVal * 0.50], 'g--', 'LineWidth', 1.5); % 50% density
    hold off;
    xlabel('Snow Depth [cm]', 'FontSize', 13);
    ylabel('SWE [cm]', 'FontSize', 13);
    legend('Pixels', '\rho = 0.30', '\rho = 0.50', 'Location', 'northwest');
    title(sprintf('SWE vs Snow Depth - %s', dateStr), 'FontSize', 14);
    set(gca, 'FontSize', 12, 'FontWeight', 'bold');
    grid on;

    % Compute mean bulk density
    meanDensity = mean(swe_px ./ dep_px, 'omitnan');
    text(0.95, 0.05, sprintf('Mean \\rho_{bulk} = %.2f', meanDensity), ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', ...
        'FontSize', 13, 'FontWeight', 'bold', 'BackgroundColor', 'w');
end

% Subplot 2: Bulk density map
subplot(2, 1, 2);
density_map = NaN(size(SWE_map));
validPx = SWE_map > 0 & Depth_map > 0 & ~isnan(SWE_map) & ~isnan(Depth_map);
density_map(validPx) = SWE_map(validPx) ./ Depth_map(validPx);

h = imagesc(plot_x, plot_y, density_map);
set(h, 'AlphaData', ~isnan(density_map));
set(gca, 'YDir', 'normal');
hold on;
if hasShapefile
    plot(plot_shp_x, plot_shp_y, 'k-', 'LineWidth', 2);
end
plot(plot_snotel_x, plot_snotel_y, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
for si = 1:snotel.nStations
    text(plot_snotel_x(si), plot_snotel_y(si), ['  ' snotel.name{si}], ...
        'FontSize', 8, 'FontWeight', 'bold', 'Color', 'r');
end
hold off;

colorbar;
cmap_density = [1 1 1; parula(255)];
colormap(gca, cmap_density);
caxis([0 0.6]);
set(gca, 'FontSize', 12, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel(xLabel);
ylabel(yLabel);
title(sprintf('SNODAS - Bulk Snow Density [SWE/Depth] - %s\nBoise River Basin, WY%d', ...
    dateStr, WY), 'FontSize', 14);
axis equal tight;

print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SNODAS_density_WY%d_day%03d.png', WY, dayIdx)));

%% ====== SUMMARY STATS ======
fprintf('\n=== Summary for WY%d (day %d = %s) ===\n', WY, dayIdx, dateStr);
fprintf('Basin mean SWE:    %.1f cm\n', meanSWE(dayIdx) * 100);
fprintf('Basin max SWE:     %.1f cm\n', max(SWE_map(:) * 100, [], 'omitnan'));
fprintf('Basin mean Depth:  %.1f cm\n', meanDepth(dayIdx) * 100);
fprintf('Basin max Depth:   %.1f cm\n', max(Depth_map(:) * 100, [], 'omitnan'));
fprintf('Basin mean Melt:   %.2f mm\n', meanMelt(dayIdx) * 1000);
if exist('meanDensity', 'var')
    fprintf('Mean bulk density: %.2f\n', meanDensity);
end

% Peak SWE date
[peakSWE, peakIdx] = max(meanSWE);
fprintf('\nPeak basin-mean SWE: %.1f cm on %s\n', ...
    peakSWE * 100, datestr(Snodas.dates(peakIdx), 'dd-mmm-yyyy'));

fprintf('\nFigures saved to: %s\n', dataDir);
fprintf('Done!\n');
