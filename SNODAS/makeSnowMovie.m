function makeSnowMovie(dataStruct, varName, movieFile, varargin)
% makeSnowMovie - Create MP4 movie of a snow variable over a water year
%
% USAGE:
%   makeSnowMovie(dataStruct, varName, movieFile)
%   makeSnowMovie(dataStruct, varName, movieFile, 'Name', Value, ...)
%
% INPUTS:
%   dataStruct - Structure from getSNODAS_WY or getUCLA_SWE
%   varName    - Variable to animate (see plotSnowVar for list)
%   movieFile  - Output filename (e.g. 'SNODAS_SWE_WY2020.mp4')
%
% OPTIONAL NAME-VALUE PAIRS:
%   'clim'       - Color limits [cmin cmax] (default: auto from data)
%   'cmap'       - Colormap name or matrix (default: varies by variable)
%   'fps'        - Frames per second (default: 10)
%   'quality'    - Video quality 0-100 (default: 90)
%   'shapefile'  - Path to shapefile overlay
%   'dateRange'  - [startDate endDate] as datenums to subset the movie
%   'titlePrefix'- Prefix string for title (default: auto-detect source)
%   'skipDays'   - Plot every Nth day (default: 1 = every day)
%   'latlim'     - Latitude limits [latmin latmax]
%   'lonlim'     - Longitude limits [lonmin lonmax]
%   'figSize'    - Figure size [width height] in pixels (default: [1280 720])
%
% EXAMPLE:
%   load SNODAS_WY2020.mat
%   makeSnowMovie(Snodas, 'SWE', 'SNODAS_SWE_WY2020.mp4', ...
%       'shapefile', 'BRB_outline.shp', 'fps', 12);
%
%   load UCLA_SWE_WY2020.mat
%   makeSnowMovie(UCLA, 'SWE_mean', 'UCLA_SWE_WY2020.mp4', 'fps', 15);
%
% HP Marshall, Boise State University
% SnowFusion Project

%% Parse inputs
p = inputParser;
addRequired(p, 'dataStruct', @isstruct);
addRequired(p, 'varName', @ischar);
addRequired(p, 'movieFile', @ischar);
addParameter(p, 'clim', [], @(x) isnumeric(x) && length(x)==2);
addParameter(p, 'cmap', '', @(x) ischar(x) || isnumeric(x));
addParameter(p, 'fps', 10, @isnumeric);
addParameter(p, 'quality', 90, @isnumeric);
addParameter(p, 'shapefile', '', @ischar);
addParameter(p, 'dateRange', [], @(x) isnumeric(x) && length(x)==2);
addParameter(p, 'titlePrefix', '', @ischar);
addParameter(p, 'skipDays', 1, @isnumeric);
addParameter(p, 'latlim', [], @(x) isnumeric(x) && length(x)==2);
addParameter(p, 'lonlim', [], @(x) isnumeric(x) && length(x)==2);
addParameter(p, 'figSize', [1280 720], @(x) isnumeric(x) && length(x)==2);
parse(p, dataStruct, varName, movieFile, varargin{:});
opts = p.Results;

%% Validate variable exists
if ~isfield(dataStruct, varName)
    flds = fieldnames(dataStruct);
    dataFlds = {};
    for f = 1:length(flds)
        if ndims(dataStruct.(flds{f})) == 3
            dataFlds{end+1} = flds{f};
        end
    end
    error('Variable "%s" not found. Available:\n  %s', ...
        varName, strjoin(dataFlds, '\n  '));
end

%% Determine date range
allDates = dataStruct.dates;
if ~isempty(opts.dateRange)
    dayIdx = find(allDates >= opts.dateRange(1) & allDates <= opts.dateRange(2));
else
    dayIdx = 1:length(allDates);
end
% Apply skipDays
dayIdx = dayIdx(1:opts.skipDays:end);
nFrames = length(dayIdx);
fprintf('Creating movie: %d frames, %s, %.1f fps\n', nFrames, varName, opts.fps);

%% Set up coordinates
lat = dataStruct.lat;
lon = dataStruct.lon;
[LON, LAT] = meshgrid(lon, lat);

% Flip if needed (SNODAS lat is north-to-south)
if lat(1) > lat(end)
    LAT = flipud(LAT);
    LON = flipud(LON);
    lat = flip(lat);
    flipData = true;
else
    flipData = false;
end

if ~isempty(opts.latlim)
    latlim = opts.latlim;
else
    latlim = [min(lat)-0.05, max(lat)+0.05];
end
if ~isempty(opts.lonlim)
    lonlim = opts.lonlim;
else
    lonlim = [min(lon)-0.05, max(lon)+0.05];
end

%% Determine color limits from full dataset if not provided
if isempty(opts.clim)
    % Sample the data to find good color limits
    allData = dataStruct.(varName);
    validData = allData(allData > 0 & ~isnan(allData));
    if ~isempty(validData)
        opts.clim = [0, prctile(validData(:), 98)];
    else
        opts.clim = [0 1];
    end
end

%% Get default colormap and units
[defCmap, ~, defUnits] = getVarDefaults(varName);
if isempty(opts.cmap), opts.cmap = defCmap; end

%% Determine title prefix
if isempty(opts.titlePrefix)
    if any(isfield(dataStruct, {'SWE_mean','fSCA_mean','SD_mean'}))
        opts.titlePrefix = 'UCLA SWE';
    else
        opts.titlePrefix = 'SNODAS';
    end
end

%% Set up the first frame
hFig = figure('Renderer', 'opengl', 'Color', 'w');
set(hFig, 'Position', [50 50 opts.figSize(1) opts.figSize(2)]);

% Extract first frame data
d = dayIdx(1);
S = dataStruct.(varName)(:,:,d);
if flipData, S = flipud(S); end
Amap = ones(size(S));
Amap(S == 0) = 0;
Amap(isnan(S)) = 0;

% Create the map
hAx = usamap(latlim, lonlim);
set(hAx, 'NextPlot', 'replacechildren');

hGeo = geoshow(LAT, LON, S, 'DisplayType', 'texturemap');
set(hGeo, 'FaceColor', 'texturemap', 'CData', S);
set(hGeo, 'EdgeColor', 'none', 'FaceAlpha', 'texture', 'AlphaData', Amap);
set(hGeo, 'BackFaceLighting', 'unlit');

if ischar(opts.cmap)
    colormap(opts.cmap);
else
    colormap(opts.cmap);
end
caxis(opts.clim);

hC = colorbar('Location', 'southoutside');
set(hC, 'FontSize', 11, 'FontWeight', 'bold');
ylabel(hC, defUnits, 'FontSize', 12, 'FontWeight', 'bold');
setm(hAx, 'FontSize', 12, 'FontWeight', 'bold');

% Overlay shapefile
if ~isempty(opts.shapefile) && exist(opts.shapefile, 'file')
    hold on;
    [Shp, ~] = shaperead(opts.shapefile);
    if max(Shp.X) > 360
        myUTM = utmzone(mean(latlim), mean(lonlim));
        mstruct = defaultm('utm');
        mstruct.zone = myUTM;
        mstruct = defaultm(mstruct);
        [Shp.lat, Shp.lon] = minvtran(mstruct, Shp.X, Shp.Y);
        plot3m(Shp.lat, Shp.lon, 100*ones(size(Shp.lat)), ...
            'Color', [0.3 0.3 0.3], 'LineWidth', 2.5);
    else
        plot3m(Shp.Y, Shp.X, 100*ones(size(Shp.X)), ...
            'Color', [0.3 0.3 0.3], 'LineWidth', 2.5);
    end
end

% Title
dateStr = datestr(allDates(d), 'yyyy-mm-dd');
hTitle = title(sprintf('%s  %s  %s', opts.titlePrefix, varName, dateStr), ...
    'FontSize', 15, 'FontWeight', 'bold');

drawnow;

%% Set up video writer
writerObj = VideoWriter(movieFile, 'MPEG-4');
writerObj.FrameRate = opts.fps;
writerObj.Quality = opts.quality;
open(writerObj);

% Write first frame
frame = getframe(hFig);
writeVideo(writerObj, frame);

%% Loop over remaining frames
fprintf('  Rendering frames: ');
tic;
for fi = 2:nFrames
    d = dayIdx(fi);

    % Extract data
    S = dataStruct.(varName)(:,:,d);
    if flipData, S = flipud(S); end
    Amap = ones(size(S));
    Amap(S == 0) = 0;
    Amap(isnan(S)) = 0;

    % Update the texture map
    set(hGeo, 'CData', S, 'AlphaData', Amap);

    % Update title with date
    dateStr = datestr(allDates(d), 'yyyy-mm-dd');
    set(hTitle, 'String', sprintf('%s  %s  %s', opts.titlePrefix, varName, dateStr));

    drawnow;
    frame = getframe(hFig);
    writeVideo(writerObj, frame);

    % Progress indicator
    if mod(fi, 50) == 0
        fprintf('%d/%d ', fi, nFrames);
    end
end
elapsed = toc;
fprintf('\n');

%% Finalize
close(writerObj);
close(hFig);
fprintf('Movie saved: %s (%d frames, %.1f sec render time)\n', ...
    movieFile, nFrames, elapsed);

end

%% Helper: default colormap, color limits, and units for each variable
function [cmap, clim, units] = getVarDefaults(varName)
    switch lower(varName)
        case {'swe', 'swe_mean', 'swe_median', 'swe_p25', 'swe_p75'}
            cmap = 'parula';
            clim = [0 1.0];
            units = 'SWE [m]';
        case 'swe_std'
            cmap = 'hot';
            clim = [0 0.3];
            units = 'SWE Std Dev [m]';
        case {'depth', 'sd_mean', 'sd_median'}
            cmap = 'cool';
            clim = [0 3.0];
            units = 'Snow Depth [m]';
        case 'sd_std'
            cmap = 'hot';
            clim = [0 1.0];
            units = 'Snow Depth Std Dev [m]';
        case {'fsca_mean', 'fsca'}
            cmap = 'gray';
            clim = [0 1.0];
            units = 'Fractional Snow Cover [-]';
        case 'precip'
            cmap = 'winter';
            clim = [0 0.05];
            units = 'Precipitation [m]';
        case {'snowprecip'}
            cmap = 'winter';
            clim = [0 0.05];
            units = 'Snow Precip [m WE]';
        case 'tsnow'
            cmap = 'jet';
            clim = [250 275];
            units = 'Snow Temperature [K]';
        case 'melt'
            cmap = 'autumn';
            clim = [0 0.02];
            units = 'Snowmelt [m]';
        case {'sublimation', 'sublimationbs'}
            cmap = 'copper';
            clim = [0 0.005];
            units = 'Sublimation [m]';
        otherwise
            cmap = 'parula';
            clim = [];
            units = varName;
    end
end
