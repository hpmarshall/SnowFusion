% plotUCLA_SR_BRB.m
% Visualize WUS UCLA Snow Reanalysis data over the Boise River Basin
%
% Reads downloaded NetCDF tiles, mosaics them, clips to BRB shapefile,
% and creates maps of SWE, fSCA, and snow depth.
%
% REQUIRES:
%   - Downloaded NetCDF files in ./data/ (run getUCLA_SR_BRB.m first)
%   - BRB_outline.shp (with .dbf, .shx, .prj companion files)
%   - Mapping Toolbox (for UTM conversion and map display)
%
% HP Marshall, Boise State University
% Created: April 2026

clear; clc; close all;

%% ====== CONFIGURATION ======
dataRoot = '/Users/hpmarshall/DATA_DRIVE/SnowFusion';
dataDir = fullfile(dataRoot, 'UCLA_SR');  % directory with .nc files
scriptDir = fileparts(mfilename('fullpath'));
shpFile = fullfile(scriptDir, 'BRB_outline.shp');  % BRB shapefile (UTM Zone 11N)
wyStr   = 'WY2020_21';                    % water year string

% Tiles covering BRB
latTiles = [43 44];
lonTiles = [115 116 117];

% Date of interest (day of water year, 1 = Oct 1)
% Common dates: April 1 SWE = day 183, Peak SWE ~ day 150-200
targetDate = 183; % April 1 (standard date for peak SWE assessment)

% Ensemble statistic to plot (1=mean, 2=std, 3=25th, 4=median, 5=75th)
ensIdx = 1; % ensemble mean

%% ====== READ AND MOSAIC TILES ======
fprintf('Reading and mosaicing UCLA SR tiles...\n');
[lat, lon, SWE, fSCA, SD] = mosaicUCLA_SR(dataDir, wyStr, latTiles, lonTiles);
fprintf('Grid size: %d lat x %d lon\n', length(lat), length(lon));

%% ====== LOAD AND CONVERT BRB SHAPEFILE ======
fprintf('Loading BRB shapefile...\n');
[S, A] = shaperead(shpFile);

% Shapefile is in UTM Zone 11N (NAD83) - convert to geographic coordinates
mstruct = defaultm('utm');
mstruct.zone = '11T';  % UTM Zone 11 (covers BRB)
mstruct = defaultm(mstruct);
[S_lat, S_lon] = minvtran(mstruct, S.X, S.Y);

% Remove NaN boundary markers for polygon operations
validIdx = ~isnan(S_lat) & ~isnan(S_lon);

fprintf('BRB extent: lat [%.2f, %.2f], lon [%.2f, %.2f]\n', ...
    min(S_lat(validIdx)), max(S_lat(validIdx)), ...
    min(S_lon(validIdx)), max(S_lon(validIdx)));

%% ====== CREATE MASK FOR BRB ======
[LON, LAT] = meshgrid(lon, lat);
inBRB = inpolygon(LON, LAT, S_lon, S_lat);
fprintf('Pixels inside BRB: %d of %d (%.1f%%)\n', ...
    sum(inBRB(:)), numel(inBRB), 100*sum(inBRB(:))/numel(inBRB));

%% ====== EXTRACT DATA FOR TARGET DATE ======
% Get ensemble mean for target date
SWE_map  = SWE(:, :, ensIdx, targetDate);   % [m]
fSCA_map = fSCA(:, :, ensIdx, targetDate);   % [0-1]
SD_map   = SD(:, :, ensIdx, targetDate);     % [m]

% Apply BRB mask
SWE_map(~inBRB)  = NaN;
fSCA_map(~inBRB) = NaN;
SD_map(~inBRB)   = NaN;

% Convert water year day to calendar date for title
wy_start = datetime(2020, 10, 1); % WY2021 starts Oct 1, 2020
target_datetime = wy_start + days(targetDate - 1);
dateStr = datestr(target_datetime, 'dd-mmm-yyyy');

%% ====== FIGURE 1: SWE MAP ======
figure(1); clf;
set(gcf, 'Position', [50 50 900 700], 'Color', 'w');

imagesc(lon, lat, SWE_map * 100); % convert m to cm
set(gca, 'YDir', 'normal');
hold on;
plot(S_lon, S_lat, 'k-', 'LineWidth', 2);
hold off;

colorbar;
colormap(parula);
caxis([0 max(SWE_map(:)*100, [], 'omitnan')]);
set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel('Longitude [deg]');
ylabel('Latitude [deg]');
title(sprintf('UCLA SR - SWE [cm] - %s\nBoise River Basin, %s', dateStr, wyStr), ...
    'FontSize', 16);
axis tight;
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SWE_%s_day%03d.png', wyStr, targetDate)));

%% ====== FIGURE 2: FRACTIONAL SNOW COVER ======
figure(2); clf;
set(gcf, 'Position', [100 50 900 700], 'Color', 'w');

imagesc(lon, lat, fSCA_map * 100); % convert to percent
set(gca, 'YDir', 'normal');
hold on;
plot(S_lon, S_lat, 'k-', 'LineWidth', 2);
hold off;

colorbar;
cmap_sca = [1 1 1; parula(255)]; % white for 0%, colored for snow
colormap(cmap_sca);
caxis([0 100]);
set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel('Longitude [deg]');
ylabel('Latitude [deg]');
title(sprintf('UCLA SR - fSCA [%%] - %s\nBoise River Basin, %s', dateStr, wyStr), ...
    'FontSize', 16);
axis tight;
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_fSCA_%s_day%03d.png', wyStr, targetDate)));

%% ====== FIGURE 3: SNOW DEPTH ======
figure(3); clf;
set(gcf, 'Position', [150 50 900 700], 'Color', 'w');

imagesc(lon, lat, SD_map * 100); % convert m to cm
set(gca, 'YDir', 'normal');
hold on;
plot(S_lon, S_lat, 'k-', 'LineWidth', 2);
hold off;

colorbar;
colormap(parula);
caxis([0 max(SD_map(:)*100, [], 'omitnan')]);
set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel('Longitude [deg]');
ylabel('Latitude [deg]');
title(sprintf('UCLA SR - Snow Depth [cm] - %s\nBoise River Basin, %s', dateStr, wyStr), ...
    'FontSize', 16);
axis tight;
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SD_%s_day%03d.png', wyStr, targetDate)));

%% ====== FIGURE 4: 3-PANEL SUMMARY ======
figure(4); clf;
set(gcf, 'Position', [50 50 1600 500], 'Color', 'w');

subplot(1, 3, 1);
imagesc(lon, lat, SWE_map * 100);
set(gca, 'YDir', 'normal', 'FontSize', 12, 'FontWeight', 'bold');
hold on; plot(S_lon, S_lat, 'k-', 'LineWidth', 2); hold off;
colorbar; colormap(gca, parula);
title(sprintf('SWE [cm]\n%s', dateStr));
xlabel('Lon'); ylabel('Lat'); axis tight;

subplot(1, 3, 2);
imagesc(lon, lat, fSCA_map * 100);
set(gca, 'YDir', 'normal', 'FontSize', 12, 'FontWeight', 'bold');
hold on; plot(S_lon, S_lat, 'k-', 'LineWidth', 2); hold off;
colorbar; caxis([0 100]);
title(sprintf('fSCA [%%]\n%s', dateStr));
xlabel('Lon'); ylabel('Lat'); axis tight;

subplot(1, 3, 3);
imagesc(lon, lat, SD_map * 100);
set(gca, 'YDir', 'normal', 'FontSize', 12, 'FontWeight', 'bold');
hold on; plot(S_lon, S_lat, 'k-', 'LineWidth', 2); hold off;
colorbar; colormap(gca, parula);
title(sprintf('Snow Depth [cm]\n%s', dateStr));
xlabel('Lon'); ylabel('Lat'); axis tight;

sgtitle(sprintf('UCLA Snow Reanalysis - Boise River Basin - %s', wyStr), ...
    'FontSize', 16, 'FontWeight', 'bold');
print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_summary_%s_day%03d.png', wyStr, targetDate)));

%% ====== FIGURE 5: TIME SERIES OF BASIN-MEAN SWE ======
figure(5); clf;
set(gcf, 'Position', [50 50 1000 400], 'Color', 'w');

% Compute basin-mean SWE for each day
nDays = size(SWE, 4);
meanSWE = NaN(nDays, 1);
stdSWE  = NaN(nDays, 1);
for d = 1:nDays
    sweDay = SWE(:, :, 1, d); % ensemble mean
    sweDay(~inBRB) = NaN;
    meanSWE(d) = mean(sweDay(:), 'omitnan');
    % Also get ensemble spread (std)
    if size(SWE, 3) >= 2
        sweStd = SWE(:, :, 2, d);
        sweStd(~inBRB) = NaN;
        stdSWE(d) = mean(sweStd(:), 'omitnan');
    end
end

% Convert to calendar dates
dates = wy_start + days((1:nDays)' - 1);

% Plot
plot(dates, meanSWE * 100, 'b-', 'LineWidth', 2);
hold on;
if any(~isnan(stdSWE))
    fill([dates; flipud(dates)], ...
         [(meanSWE + stdSWE) * 100; flipud((meanSWE - stdSWE) * 100)], ...
         'b', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
end
% Mark April 1
xline(datetime(2021, 4, 1), 'r--', 'Apr 1', 'LineWidth', 1.5, 'FontSize', 12);
hold off;

set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
xlabel('Date');
ylabel('Basin Mean SWE [cm]');
title(sprintf('Boise River Basin Mean SWE - %s\nUCLA Snow Reanalysis (ensemble mean \\pm 1\\sigma)', wyStr), ...
    'FontSize', 14);
grid on;
xlim([dates(1) dates(end)]);

print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SWE_timeseries_%s.png', wyStr)));

%% ====== FIGURE 6: SWE UNCERTAINTY (Ensemble Spread) ======
figure(6); clf;
set(gcf, 'Position', [50 50 900 700], 'Color', 'w');

% Ensemble std for target date
if size(SWE, 3) >= 2
    SWE_std = SWE(:, :, 2, targetDate) * 100; % cm
    SWE_std(~inBRB) = NaN;

    imagesc(lon, lat, SWE_std);
    set(gca, 'YDir', 'normal');
    hold on; plot(S_lon, S_lat, 'k-', 'LineWidth', 2); hold off;
    colorbar;
    colormap(hot);
    set(gca, 'FontSize', 14, 'FontWeight', 'bold', 'LineWidth', 1.5);
    xlabel('Longitude [deg]');
    ylabel('Latitude [deg]');
    title(sprintf('UCLA SR - SWE Uncertainty (1\\sigma) [cm] - %s\nBoise River Basin, %s', ...
        dateStr, wyStr), 'FontSize', 14);
    axis tight;
    print('-dpng', '-r150', fullfile(dataDir, sprintf('BRB_SWE_uncertainty_%s_day%03d.png', wyStr, targetDate)));
end

%% ====== SUMMARY STATS ======
fprintf('\n=== Summary for %s (day %d = %s) ===\n', wyStr, targetDate, dateStr);
fprintf('Basin mean SWE:  %.1f cm\n', meanSWE(targetDate) * 100);
fprintf('Basin max SWE:   %.1f cm\n', max(SWE_map(:) * 100, [], 'omitnan'));
fprintf('Basin mean fSCA: %.1f %%\n', mean(fSCA_map(:) * 100, 'omitnan'));
fprintf('Basin mean SD:   %.1f cm\n', mean(SD_map(:) * 100, 'omitnan'));
fprintf('Basin max SD:    %.1f cm\n', max(SD_map(:) * 100, [], 'omitnan'));
if any(~isnan(stdSWE))
    fprintf('Basin mean SWE uncertainty: %.1f cm\n', stdSWE(targetDate) * 100);
end

fprintf('\nFigures saved to: %s\n', dataDir);
fprintf('Done!\n');
