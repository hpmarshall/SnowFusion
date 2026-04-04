% movieSNODAS_BRB.m
% Creates a water year animation (video) of SNODAS data for the BRB.
% User can select which variable to animate.
%
% Based on SNODASmovieSWE.m but updated for the new data structure
% from getSNODAS_BRB.m.
%
% REQUIRES:
%   - SNODAS_BRB_WY####.mat file from getSNODAS_BRB.m
%   - BRB_outline.shp (Boise River Basin shapefile)
%
% HP Marshall, Boise State University, April 2026

clear; clc;

%% ====== USER CONFIGURATION ======
WY      = 2024;           % Water year
plotVar = 'SWE';          % Variable to animate
fps     = 10;             % Frames per second for video

% Options: 'Precip','SnowPrecip','SWE','Depth','Tsnow',
%          'SublimationBS','Melt','Sublimation'

%% ====== LOAD DATA ======
dataDir = fullfile(pwd, 'data_BRB');
matFile = fullfile(dataDir, sprintf('SNODAS_BRB_WY%d.mat', WY));

if ~exist(matFile, 'file')
    error('Data file not found: %s\nRun getSNODAS_BRB.m first.', matFile);
end

fprintf('Loading %s...\n', matFile);
load(matFile, 'Snodas');

lat = Snodas.lat;
lon = Snodas.lon;
[LON, LAT] = meshgrid(lon, lat);
dates = Snodas.dates;
nDays = length(dates);

%% ====== SET UP VARIABLE-SPECIFIC PARAMETERS ======
switch plotVar
    case 'SWE'
        cLabel = 'SWE [m]';
        cRange = [0 1.5];
        cMap   = parula;
        titleBase = 'Snow Water Equivalent';
    case 'Depth'
        cLabel = 'Snow Depth [m]';
        cRange = [0 3.0];
        cMap   = parula;
        titleBase = 'Snow Depth';
    case 'Precip'
        cLabel = 'Precipitation [mm]';
        cRange = [0 50];
        cMap   = flipud(hot);
        titleBase = 'Precipitation';
    case 'SnowPrecip'
        cLabel = 'Snowfall [mm w.e.]';
        cRange = [0 50];
        cMap   = flipud(hot);
        titleBase = 'Snowfall';
    case 'Tsnow'
        cLabel = 'Temperature [K]';
        cRange = [240 273];
        cMap   = cool;
        titleBase = 'Snow Temperature';
    case 'Melt'
        cLabel = 'Melt [m]';
        cRange = [0 0.05];
        cMap   = hot;
        titleBase = 'Snow Melt';
    case 'Sublimation'
        cLabel = 'Sublimation [m]';
        cRange = [0 0.01];
        cMap   = copper;
        titleBase = 'Sublimation';
    case 'SublimationBS'
        cLabel = 'Blowing Snow Sublimation [m]';
        cRange = [0 0.005];
        cMap   = copper;
        titleBase = 'Blowing Snow Sublimation';
    otherwise
        error('Unknown variable: %s', plotVar);
end

%% ====== LOAD SHAPEFILE ======
shpFile = fullfile(fileparts(mfilename('fullpath')), 'BRB_outline.shp');
if ~exist(shpFile, 'file')
    shpFile = 'BRB_outline.shp';
end
hasShp = exist(shpFile, 'file');

latlim = [min(lat) max(lat)];
lonlim = [min(lon) max(lon)];

if hasShp
    [Shp, ~] = shaperead(shpFile);
    if license('test', 'map_toolbox')
        myUTM = utmzone(mean(latlim), mean(lonlim));
        mstruct = defaultm('utm');
        mstruct.zone = myUTM;
        mstruct = defaultm(mstruct);
        [Shp.lat, Shp.lon] = minvtran(mstruct, Shp.X, Shp.Y);
    end
end

%% ====== SET UP FIGURE ======
hfig = figure('Position', [100 100 1000 800], 'Color', 'w', ...
    'Renderer', 'opengl');

% First frame
data = Snodas.(plotVar)(:,:,1);
Amap = ones(size(data));
Amap(isnan(data)) = 0;
Amap(data == 0) = 0;

if license('test', 'map_toolbox')
    % Mapping Toolbox version
    ax = usamap(latlim, lonlim);
    hG = geoshow(LAT, LON, data, 'DisplayType', 'texturemap');
    set(hG, 'FaceColor', 'texturemap', 'CData', data);
    set(hG, 'EdgeColor', 'none', 'FaceAlpha', 'texture', 'AlphaData', Amap);
    colormap(cMap);
    caxis(cRange);
    hcb = colorbar('Location', 'southoutside');
    ylabel(hcb, cLabel, 'FontSize', 12, 'FontWeight', 'bold');
    if hasShp
        hold on;
        plot3m(Shp.lat, Shp.lon, 100*ones(size(Shp.lat)), ...
            'Color', [0.3 0.3 0.3], 'LineWidth', 3);
    end
    setm(ax, 'FontSize', 14, 'FontWeight', 'bold');
    useMap = true;
else
    % Simple imagesc version
    hG = imagesc(lon, lat, data);
    set(gca, 'YDir', 'normal');
    set(hG, 'AlphaData', Amap);
    hold on;
    colormap(cMap);
    caxis(cRange);
    hcb = colorbar;
    ylabel(hcb, cLabel, 'FontSize', 12);
    xlabel('Longitude');
    ylabel('Latitude');
    set(gca, 'FontSize', 14, 'FontWeight', 'bold');
    axis tight;
    useMap = false;
end

hTitle = title(sprintf('SNODAS %s - BRB - %s', titleBase, ...
    datestr(dates(1), 'yyyy-mm-dd')), 'FontSize', 16);

%% ====== CREATE VIDEO ======
videoFile = fullfile(dataDir, sprintf('SNODAS_BRB_%s_WY%d.mp4', plotVar, WY));
writerObj = VideoWriter(videoFile, 'MPEG-4');
writerObj.FrameRate = fps;
writerObj.Quality = 95;
open(writerObj);

fprintf('Creating animation: %s\n', videoFile);
fprintf('  %d frames at %d fps = %.1f seconds\n', nDays, fps, nDays/fps);

% Write first frame
drawnow;
frame = getframe(hfig);
writeVideo(writerObj, frame);

% Animate remaining frames
for d = 2:nDays
    data = Snodas.(plotVar)(:,:,d);
    Amap = ones(size(data));
    Amap(isnan(data)) = 0;
    Amap(data == 0) = 0;

    if useMap
        set(hG, 'CData', data, 'AlphaData', Amap);
    else
        set(hG, 'CData', data, 'AlphaData', Amap);
    end

    set(hTitle, 'String', sprintf('SNODAS %s - BRB - %s', titleBase, ...
        datestr(dates(d), 'yyyy-mm-dd')));

    drawnow;
    frame = getframe(hfig);
    writeVideo(writerObj, frame);

    if mod(d, 30) == 0
        fprintf('  Frame %d/%d (%s)\n', d, nDays, datestr(dates(d)));
    end
end

close(writerObj);
fprintf('\nVideo saved: %s\n', videoFile);
fprintf('Duration: %.1f seconds at %d fps\n', nDays/fps, fps);
