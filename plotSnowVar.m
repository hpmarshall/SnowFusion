function [hFig, hGeo] = plotSnowVar(dataStruct, varName, targetDate, varargin)
% plotSnowVar - Plot a snow variable for a single date from SNODAS or UCLA data
%
% USAGE:
%   [hFig, hGeo] = plotSnowVar(dataStruct, varName, targetDate)
%   [hFig, hGeo] = plotSnowVar(dataStruct, varName, targetDate, 'Name', Value, ...)
%
% INPUTS:
%   dataStruct - Structure from getSNODAS_WY or getUCLA_SWE
%   varName    - Variable to plot (see list below)
%   targetDate - Date as datenum, datestr, or datetime
%
% OPTIONAL NAME-VALUE PAIRS:
%   'clim'       - Color limits [cmin cmax] (auto if empty)
%   'cmap'       - Colormap name or matrix (default: varies by variable)
%   'title'      - Custom title string
%   'shapefile'  - Path to shapefile to overlay (e.g. 'BRB_outline.shp')
%   'figHandle'  - Existing figure handle to plot into
%   'saveFig'    - Filename to save figure (e.g. 'SWE_2020-03-15.png')
%   'units'      - Override units string for colorbar
%   'latlim'     - Latitude limits for map [latmin latmax]
%   'lonlim'     - Longitude limits for map [lonmin lonmax]
%
% SNODAS VARIABLES:
%   'SWE'           - Snow Water Equivalent [m]
%   'Depth'         - Snow Depth [m]
%   'Precip'        - Precipitation [m]
%   'SnowPrecip'    - Snow Precipitation [m WE]
%   'Tsnow'         - Snow Temperature [K]
%   'Melt'          - Snowmelt [m]
%   'Sublimation'   - Pack Sublimation [m]
%   'SublimationBS' - Blowing Snow Sublimation [m]
%
% UCLA SWE VARIABLES:
%   'SWE_mean'      - SWE posterior mean [m]
%   'SWE_median'    - SWE posterior median [m]
%   'SWE_std'       - SWE posterior std dev [m]
%   'SWE_p25'       - SWE 25th percentile [m]
%   'SWE_p75'       - SWE 75th percentile [m]
%   'fSCA_mean'     - Fractional snow covered area [-]
%   'SD_mean'       - Snow depth mean [m]
%   'SD_median'     - Snow depth median [m]
%   'SD_std'        - Snow depth std dev [m]
%
% OUTPUT:
%   hFig - Figure handle
%   hGeo - geoshow handle (for updating in movies)
%
% EXAMPLE:
%   load SNODAS_WY2020.mat
%   plotSnowVar(Snodas, 'SWE', '2020-04-01');
%
%   load UCLA_SWE_WY2020.mat
%   plotSnowVar(UCLA, 'SWE_mean', '2020-04-01', 'shapefile', 'BRB_outline.shp');
%
% HP Marshall, Boise State University
% SnowFusion Project

%% Parse inputs
p = inputParser;
addRequired(p, 'dataStruct', @isstruct);
addRequired(p, 'varName', @ischar);
addRequired(p, 'targetDate');
addParameter(p, 'clim', [], @(x) isnumeric(x) && length(x)==2);
addParameter(p, 'cmap', '', @(x) ischar(x) || isnumeric(x));
addParameter(p, 'title', '', @ischar);
addParameter(p, 'shapefile', '', @ischar);
addParameter(p, 'figHandle', [], @(x) ishandle(x));
addParameter(p, 'saveFig', '', @ischar);
addParameter(p, 'units', '', @ischar);
addParameter(p, 'latlim', [], @(x) isnumeric(x) && length(x)==2);
addParameter(p, 'lonlim', [], @(x) isnumeric(x) && length(x)==2);
addParameter(p, 'snotel', true, @islogical);
parse(p, dataStruct, varName, targetDate, varargin{:});
opts = p.Results;

%% Convert target date to datenum
if ischar(targetDate) || isstring(targetDate)
    targetDN = datenum(targetDate);
elseif isa(targetDate, 'datetime')
    targetDN = datenum(targetDate);
else
    targetDN = targetDate;
end

%% Find date index
if isfield(dataStruct, 'dates')
    [~, dayIdx] = min(abs(dataStruct.dates - targetDN));
    actualDate = dataStruct.dates(dayIdx);
    if abs(actualDate - targetDN) > 1
        warning('Closest date is %s (requested %s)', ...
            datestr(actualDate), datestr(targetDN));
    end
else
    error('Data structure must have a .dates field');
end

%% Extract the variable for this date
if ~isfield(dataStruct, varName)
    % List available variables
    flds = fieldnames(dataStruct);
    dataFlds = {};
    for f = 1:length(flds)
        if ndims(dataStruct.(flds{f})) == 3
            dataFlds{end+1} = flds{f};
        end
    end
    error('Variable "%s" not found. Available 3D variables:\n  %s', ...
        varName, strjoin(dataFlds, '\n  '));
end

S = dataStruct.(varName)(:,:,dayIdx);

%% Set up coordinates
lat = dataStruct.lat;
lon = dataStruct.lon;
[LON, LAT] = meshgrid(lon, lat);

% Ensure lat is oriented correctly for mapping
if lat(1) > lat(end)
    % lat is north-to-south (SNODAS style), flip for display
    S = flipud(S);
    LAT = flipud(LAT);
    LON = flipud(LON);
    lat = flip(lat);
end

%% Determine map limits
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

%% Set default colormap and units based on variable
[defCmap, defClim, defUnits] = getVarDefaults(varName);
if isempty(opts.cmap), opts.cmap = defCmap; end
if isempty(opts.clim), opts.clim = defClim; end
if isempty(opts.units), opts.units = defUnits; end

%% Create figure
if ~isempty(opts.figHandle)
    hFig = opts.figHandle;
    figure(hFig); clf;
else
    hFig = figure('Renderer', 'opengl', 'Color', 'w');
    set(hFig, 'Position', [100 100 900 700]);
end

%% Create map
hAx = usamap(latlim, lonlim);
set(hAx, 'NextPlot', 'replacechildren');

% Create alpha mask (transparent where no snow / NaN)
Amap = ones(size(S));
Amap(S == 0) = 0;
Amap(isnan(S)) = 0;

% Plot data as texture map
hGeo = geoshow(LAT, LON, S, 'DisplayType', 'texturemap');
set(hGeo, 'FaceColor', 'texturemap', 'CData', S);
set(hGeo, 'EdgeColor', 'none', 'FaceAlpha', 'texture', 'AlphaData', Amap);
set(hGeo, 'BackFaceLighting', 'unlit');

% Apply colormap
if ischar(opts.cmap)
    colormap(opts.cmap);
else
    colormap(opts.cmap);
end

% Apply color limits
if ~isempty(opts.clim)
    caxis(opts.clim);
else
    % Auto scale, ignoring NaN and zeros
    validData = S(S > 0 & ~isnan(S));
    if ~isempty(validData)
        caxis([0 prctile(validData, 98)]);
    end
end

% Colorbar
hC = colorbar('Location', 'southoutside');
set(hC, 'FontSize', 12, 'FontWeight', 'bold');
ylabel(hC, opts.units, 'FontSize', 13, 'FontWeight', 'bold');

% Map formatting
setm(hAx, 'FontSize', 14, 'FontWeight', 'bold');

%% Overlay shapefile if provided
if ~isempty(opts.shapefile) && exist(opts.shapefile, 'file')
    [Shp, ~] = shaperead(opts.shapefile);
    % Convert UTM to lat/lon if needed
    if max(Shp.X) > 360 % UTM coordinates
        myUTM = utmzone(mean(latlim), mean(lonlim));
        mstruct = defaultm('utm');
        mstruct.zone = myUTM;
        mstruct = defaultm(mstruct);
        [Shp.lat, Shp.lon] = minvtran(mstruct, Shp.X, Shp.Y);
        plot3m(Shp.lat, Shp.lon, 100*ones(size(Shp.lat)), ...
            'Color', [0.3 0.3 0.3], 'LineWidth', 3);
    else
        plot3m(Shp.Y, Shp.X, 100*ones(size(Shp.X)), ...
            'Color', [0.3 0.3 0.3], 'LineWidth', 3);
    end
end

%% Overlay SNOTEL sites
if opts.snotel
    snotel = getSNOTEL_BRB();
    plot3m(snotel.lat, snotel.lon, 100*ones(size(snotel.lat)), ...
        'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
end

%% Title
if ~isempty(opts.title)
    titleStr = opts.title;
else
    % Determine data source
    if isfield(dataStruct, 'WY')
        srcStr = sprintf('WY%d', dataStruct.WY);
    else
        srcStr = '';
    end
    % Detect source type
    if any(isfield(dataStruct, {'SWE_mean','fSCA_mean','SD_mean'}))
        srcName = 'UCLA SWE';
    else
        srcName = 'SNODAS';
    end
    titleStr = sprintf('%s %s - %s  %s', srcName, varName, ...
        datestr(actualDate, 'yyyy-mm-dd'), srcStr);
end
title(titleStr, 'FontSize', 16, 'FontWeight', 'bold');

%% Save figure if requested
if ~isempty(opts.saveFig)
    print(hFig, opts.saveFig, '-dpng', '-r200');
    fprintf('Figure saved to %s\n', opts.saveFig);
end

end

%% Helper: default colormap, color limits, and units for each variable
function [cmap, clim, units] = getVarDefaults(varName)
    switch lower(varName)
        case {'swe', 'swe_mean', 'swe_median', 'swe_p25', 'swe_p75'}
            cmap = 'parula';
            clim = [0 1.0];     % 0 to 1 m
            units = 'SWE [m]';
        case 'swe_std'
            cmap = 'hot';
            clim = [0 0.3];
            units = 'SWE Std Dev [m]';
        case {'depth', 'sd_mean', 'sd_median'}
            cmap = 'cool';
            clim = [0 3.0];     % 0 to 3 m
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
