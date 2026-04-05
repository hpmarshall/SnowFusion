function snotel = getSNOTEL_BRB(shpPath, latLim, lonLim)
% getSNOTEL_BRB - Load SNOTEL sites from shapefile, optionally filtered by bounding box
%
% USAGE:
%   snotel = getSNOTEL_BRB(shpPath)
%   snotel = getSNOTEL_BRB(shpPath, latLim, lonLim)
%
% INPUTS:
%   shpPath  - path to SNOTEL shapefile (IDDCO_2020_automated_sites.shp)
%   latLim   - [latMin latMax] bounding box latitude limits (optional)
%   lonLim   - [lonMin lonMax] bounding box longitude limits (optional)
%
% OUTPUT:
%   snotel - Structure with fields:
%       .name      - cell array of station names
%       .siteNum   - vector of NRCS site numbers
%       .lat       - vector of latitudes  (decimal degrees N)
%       .lon       - vector of longitudes (decimal degrees E, negative = W)
%       .elev_ft   - vector of elevations (feet)
%       .nStations - number of stations
%
% Coordinates are read from the DBF attributes (decimal degrees, WGS84).
%
% HP Marshall, Boise State University
% SnowFusion Project, April 2026

if nargin < 2 || isempty(latLim)
    latLim = [-Inf Inf];
end
if nargin < 3 || isempty(lonLim)
    lonLim = [-Inf Inf];
end

% Read shapefile (DBF attributes contain precise decimal-degree lat/lon)
S = shaperead(shpPath);

nAll    = length(S);
names   = cell(nAll, 1);
siteNum = zeros(nAll, 1);
lats    = zeros(nAll, 1);
lons    = zeros(nAll, 1);
elevs   = zeros(nAll, 1);

for i = 1:nAll
    names{i}   = S(i).sta_nm;
    siteNum(i) = S(i).Ntwk_Id;
    lats(i)    = S(i).lat;
    lons(i)    = S(i).lon;
    elevs(i)   = S(i).elev;
end

% Filter by bounding box
keep = lats >= latLim(1) & lats <= latLim(2) & ...
       lons >= lonLim(1) & lons <= lonLim(2);

snotel.name      = names(keep);
snotel.siteNum   = siteNum(keep);
snotel.lat       = lats(keep);
snotel.lon       = lons(keep);
snotel.elev_ft   = elevs(keep);
snotel.nStations = sum(keep);

end
