% diagnoseTiles.m - Diagnostic script to check tile coordinate ordering
% Run this from SnowFusion/ directory

dataDir = '/Users/hpmarshall/DATA_DRIVE/SnowFusion/UCLA_SR';
wyStr = 'WY2020_21';
latTiles = [43 44];
lonTiles = [115 116 117];

fprintf('=== Tile Coordinate Diagnostics ===\n\n');

for iLat = 1:length(latTiles)
    for iLon = 1:length(lonTiles)
        tileStr = sprintf('N%d_0W%d_0', latTiles(iLat), lonTiles(iLon));

        % Find SWE_SCA file
        f = dir(fullfile(dataDir, sprintf('*%s*%s*SWE_SCA_POST*.nc', tileStr, wyStr)));
        if isempty(f); continue; end

        fname = fullfile(dataDir, f(1).name);
        lat = ncread(fname, 'Latitude');
        lon = ncread(fname, 'Longitude');

        % Read a single day slice of SWE (day 183 = Apr 1, ensemble mean)
        swe = ncread(fname, 'SWE_Post');
        sweSlice = swe(:,:,1,183);  % [dim1 x dim2]

        fprintf('Tile: %s\n', tileStr);
        fprintf('  File: %s\n', f(1).name);
        fprintf('  Lat: size=%s, range=[%.4f, %.4f], first3=[%.4f %.4f %.4f], last3=[%.4f %.4f %.4f]\n', ...
            mat2str(size(lat)), min(lat), max(lat), ...
            lat(1), lat(2), lat(3), lat(end-2), lat(end-1), lat(end));
        fprintf('  Lon: size=%s, range=[%.4f, %.4f], first3=[%.4f %.4f %.4f], last3=[%.4f %.4f %.4f]\n', ...
            mat2str(size(lon)), min(lon), max(lon), ...
            lon(1), lon(2), lon(3), lon(end-2), lon(end-1), lon(end));
        fprintf('  Lat ascending? %d   Lon ascending? %d\n', ...
            issorted(lat), issorted(lon));
        fprintf('  SWE_Post size: %s (raw ncread)\n', mat2str(size(swe)));
        fprintf('  SWE slice(:,:,1,183) size: %s\n', mat2str(size(sweSlice)));
        fprintf('  SWE slice: mean=%.4f, NaN%%=%.1f%%\n', ...
            mean(sweSlice(:), 'omitnan'), 100*sum(isnan(sweSlice(:)))/numel(sweSlice));

        % Check: which dimension corresponds to lat vs lon?
        % If dim1=225 matches lat and dim2=225 matches lon,
        % then sweSlice(i,j) = SWE at lat(i), lon(j)
        % But ncread returns in file order which is [lon x lat x ens x day] or [lat x lon x ens x day]
        fprintf('  Corner values SWE(1,1)=%.4f, SWE(end,1)=%.4f, SWE(1,end)=%.4f, SWE(end,end)=%.4f\n', ...
            sweSlice(1,1), sweSlice(end,1), sweSlice(1,end), sweSlice(end,end));
        fprintf('\n');
    end
end

fprintf('=== Check: Do adjacent tiles have matching edge coordinates? ===\n');
% Check N43_W116 right edge vs N43_W115 left edge
f116 = dir(fullfile(dataDir, '*N43_0W116_0*SWE_SCA_POST*.nc'));
f115 = dir(fullfile(dataDir, '*N43_0W115_0*SWE_SCA_POST*.nc'));
if ~isempty(f116) && ~isempty(f115)
    lon116 = ncread(fullfile(dataDir, f116(1).name), 'Longitude');
    lon115 = ncread(fullfile(dataDir, f115(1).name), 'Longitude');
    fprintf('  W116 lon range: [%.4f, %.4f]\n', min(lon116), max(lon116));
    fprintf('  W115 lon range: [%.4f, %.4f]\n', min(lon115), max(lon115));
    fprintf('  W116 right edge (last lon): %.4f\n', lon116(end));
    fprintf('  W115 left edge (first lon): %.4f\n', lon115(1));
    fprintf('  Gap between tiles: %.6f deg\n', lon115(1) - lon116(end));
end

% Check N43_W116 top edge vs N44_W116 bottom edge
f43 = dir(fullfile(dataDir, '*N43_0W116_0*SWE_SCA_POST*.nc'));
f44 = dir(fullfile(dataDir, '*N44_0W116_0*SWE_SCA_POST*.nc'));
if ~isempty(f43) && ~isempty(f44)
    lat43 = ncread(fullfile(dataDir, f43(1).name), 'Latitude');
    lat44 = ncread(fullfile(dataDir, f44(1).name), 'Latitude');
    fprintf('  N43 lat range: [%.4f, %.4f]\n', min(lat43), max(lat43));
    fprintf('  N44 lat range: [%.4f, %.4f]\n', min(lat44), max(lat44));
    fprintf('  N43 top edge (last/max lat): %.4f\n', max(lat43));
    fprintf('  N44 bottom edge (first/min lat): %.4f\n', min(lat44));
end

fprintf('\nDone. Copy output and send to Claude for analysis.\n');
