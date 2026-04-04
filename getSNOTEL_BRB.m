function snotel = getSNOTEL_BRB()
% getSNOTEL_BRB - Return SNOTEL station locations for the Boise River Basin
%
% USAGE:
%   snotel = getSNOTEL_BRB();
%
% OUTPUT:
%   snotel - Structure with fields:
%       .name      - cell array of station names
%       .siteNum   - vector of NRCS site numbers
%       .lat       - vector of latitudes  (decimal degrees N)
%       .lon       - vector of longitudes (decimal degrees E, negative = W)
%       .elev_ft   - vector of elevations (feet)
%
% Station coordinates are from the NRCS National Water and Climate Center
%   https://wcc.sc.egov.usda.gov/nwcc/sntlsites.jsp?state=ID
%
% Bounding box: lat [43.0, 44.5], lon [-116.3, -114.3]
%
% EXAMPLE:
%   snotel = getSNOTEL_BRB();
%   plot(snotel.lon, snotel.lat, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
%
% HP Marshall, Boise State University
% SnowFusion Project, April 2026

% SNOTEL stations within the Boise River Basin bounding box
% Source: NRCS AWDB (verified from individual site pages)
% Coordinates in degrees-minutes converted to decimal degrees
%
% Site#  Name                      Lat(deg-min)    Lon(deg-min)    Elev(ft)
%  306   Atlanta Summit            43 45 N         115 14 W        7960
%  312   Banner Summit             44 18 N         115 14 W        7040
%  436   Deadwood Summit           44 13 N         115 38 W        6820
%  496   Graham Guard Sta.         43 57 N         115 16 W        5680
%  550   Jackson Peak              43 39 N         115 30 W        7070
%  637   Mores Creek Summit        43 56 N         115 40 W        6090
%  710   Prairie                   43 36 N         115 15 W        5640
%  830   Trinity Mountain          43 38 N         115 26 W        7790
%  978   Bogus Basin               43 46 N         116 06 W        6370

snotel.name    = {'Atlanta Summit', 'Banner Summit', 'Deadwood Summit', ...
                  'Graham Guard Sta.', 'Jackson Peak', 'Mores Creek Summit', ...
                  'Prairie', 'Trinity Mountain', 'Bogus Basin'};

snotel.siteNum = [306, 312, 436, 496, 550, 637, 710, 830, 978];

snotel.lat     = [43+45/60, 44+18/60, 44+13/60, ...
                  43+57/60, 43+39/60, 43+56/60, ...
                  43+36/60, 43+38/60, 43+46/60];

snotel.lon     = [-(115+14/60), -(115+14/60), -(115+38/60), ...
                  -(115+16/60), -(115+30/60), -(115+40/60), ...
                  -(115+15/60), -(115+26/60), -(116+06/60)];

snotel.elev_ft = [7960, 7040, 6820, 5680, 7070, 6090, 5640, 7790, 6370];

snotel.nStations = length(snotel.name);

end
