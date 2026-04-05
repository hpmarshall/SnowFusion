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
addParameter(p, 'snotel', true, @islogical);
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

%% Load static overlays once (outside frame loop)
% Shapefile
proj = projcrs(26911);  % NAD83 / UTM Zone 11N
shpLat = [];  shpLon = [];
if ~isempty(opts.shapefile) && exist(opts.shapefile, 'file')
    [ShpData, ~] = shaperead(opts.shapefile);
    if max(ShpData.X) > 360
        [shpLat, shpLon] = projinv(proj, ShpData.X, ShpData.Y);
    else
        shpLat = ShpData.Y;
        shpLon = ShpData.X;
    end
end

% SNOTEL sites
snotel = [];
if opts.snotel
    scriptDir = fileparts(mfilename('fullpath'));
    snotelShp = fullfile(scriptDir, 'SNOTEL/IDDCO_2020_automated_sites.shp');
    snotel = getSNOTEL_BRB(snotelShp, latlim, lonlim);
end

%% Set up figure and video writer
hFig = figure('Renderer', 'opengl', 'Color', 'w');
set(hFig, 'Position', [50 50 opts.figSize(1) opts.figSize(2)]);

writerObj = VideoWriter(movieFile, 'MPEG-4');
writerObj.FrameRate = opts.fps;
writerObj.Quality = opts.quality;
open(writerObj);

%% Frame loop - redraw each frame for reliability
fprintf('  Rendering frames: ');
tic;
for fi = 1:nFrames
    d = dayIdx(fi);

    % Extract and prep data
    S = dataStruct.(varName)(:,:,d);
    if flipData, S = flipud(S); end
    Amap = double(S ~= 0 & ~isnan(S));

    % Clear and rebuild map axes
    clf(hFig);
    hAx = usamap(latlim, lonlim);
    set(hAx, 'Color', 'w');
    setm(hAx, 'FFaceColor', 'w');

    % Data layer
    hGeo = geoshow(LAT, LON, S, 'DisplayType', 'texturemap');
    set(hGeo, 'FaceColor', 'texturemap', 'CData', S);
    set(hGeo, 'EdgeColor', 'none', 'FaceAlpha', 'texture', 'AlphaData', Amap);

    colormap(opts.cmap);
    caxis(opts.clim);

    hC = colorbar('Location', 'southoutside');
    set(hC, 'FontSize', 11, 'FontWeight', 'bold');
    ylabel(hC, defUnits, 'FontSize', 12, 'FontWeight', 'bold');
    setm(hAx, 'FontSize', 12, 'FontWeight', 'bold');

    % Shapefile overlay
    if ~isempty(shpLat)
        hold on;
        plot3m(shpLat, shpLon, 100*ones(size(shpLat)), ...
            'Color', [0.3 0.3 0.3], 'LineWidth', 2.5);
    end

    % SNOTEL overlay
    if ~isempty(snotel) && snotel.nStations > 0
        hold on;
        plot3m(snotel.lat, snotel.lon, 100*ones(size(snotel.lat)), ...
            'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
    end

    % Title
    dateStr = datestr(allDates(d), 'yyyy-mm-dd');
    title(sprintf('%s  %s  %s', opts.titlePrefix, varName, dateStr), ...
        'FontSize', 15, 'FontWeight', 'bold');

    drawnow;
    frame = getframe(hFig);
    writeVideo(writerObj, frame);

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
