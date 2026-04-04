function [data, lat, lon] = loadSNODAS_var(matFile, varName)
% loadSNODAS_var - Load a single variable from a SNODAS water year .mat file
%
% USAGE:
%   [data, lat, lon] = loadSNODAS_var('data_BRB/SNODAS_BRB_WY2024.mat', 'SWE')
%
% INPUTS:
%   matFile - path to .mat file created by getSNODAS_BRB.m
%   varName - variable name: 'Precip', 'SnowPrecip', 'SWE', 'Depth',
%             'Tsnow', 'SublimationBS', 'Melt', 'Sublimation'
%
% OUTPUTS:
%   data - [nLat x nLon x nDays] array with units converted
%   lat  - latitude vector (north to south)
%   lon  - longitude vector (west to east)
%
% HP Marshall, Boise State University, April 2026

R = load(matFile);

if isfield(R, 'Snodas')
    % Full water year file
    S = R.Snodas;
    if ~isfield(S, varName)
        error('Variable "%s" not found. Available: %s', varName, ...
            strjoin(fieldnames(S), ', '));
    end
    data = S.(varName);
    lat = S.lat;
    lon = S.lon;
else
    % Single-day file
    if ~isfield(R, varName)
        error('Variable "%s" not found. Available: %s', varName, ...
            strjoin(fieldnames(R), ', '));
    end
    data = R.(varName);
    lat = R.lat;
    lon = R.lon;
end

end
