% try saving sparse SNODAS data to netCDF4

load('2014/03_Mar/S2014-3-1.mat') % load some data
%%
ncid = netcdf.create('SNODAS-140110.nc','CLOBBER'); % open netCDF file
Ixlat = netcdf.defDim(ncid,'lat',length(lat)); % define latitude dimension
vlat = netcdf.defVar(ncid,'lat','double',Ixlat); % define latitude variable
Ixlon = netcdf.defDim(ncid,'lon',length(lon)); % define latitude dimension
vlon = netcdf.defVar(ncid,'lon','double',Ixlon); % define latitude variable
vSWE = netcdf.defVar(ncid,'SWE','double',[Ixlon Ixlat]); % define latitude variable
%%
netcdf.endDef(ncid); % exit define mode
netcdf.putVar(ncid,vlat,lat); % add the data to the netCDF file
netcdf.putVar(ncid,vlon,lon); % add the data to the netCDF file
SWE=full(r(4).data);
netcdf.putVar(ncid,vSWE,SWE); % add the data to the netCDF file
netcdf.close(ncid);

%%
ncid2 = netcdf.open('SNODAS-140110.nc','NC_NOWRITE');
SWE2 = netcdf.getVar(ncid2,vSWE);
lat2= netcdf.getVar(ncid2,vlat);
lon2=netcdf.getVar(ncid2,vlon);
%%
% now first just simple plot:
SWE3=flipud(full(SWE2)');
%SWE3=fliplr(flipud(SWE3)');
Ix=find(SWE3<50 | SWE3>700);
SWE3(Ix)=NaN;
Amap=ones(size(SWE3));
Amap(Ix)=0;
%%
figure(1);clf;imagesc(lon,lat,SWE3,[50 600]); set(gca,'YDir','normal'); alpha(Amap)
%%
figure(2);clf; ax = usamap({'CA','MT'});
set(ax, 'Visible', 'off')
latlim = getm(ax, 'MapLatLimit');
lonlim = getm(ax, 'MapLonLimit');
states = shaperead('usastatehi',...
        'UseGeoCoords', true, 'BoundingBox', [lonlim', latlim']);
geoshow(ax, states, 'EdgeColor', [1 1 1]);
hold on
lonmin=-124.733749999999;
lonmax=-66.9420833333342;
latmin=24.9495833333335;
latmax=52.8745833333323;
lon=linspace(lonmin,lonmax,6935);
lat=linspace(latmax,latmin,3351);
[LON,LAT]=meshgrid(lon,lat);


%%
lat = [states.LabelLat];
lon = [states.LabelLon];
tf = ingeoquad(lat, lon, latlim, lonlim);
textm(lat(tf), lon(tf), {states(tf).Name}, ...
   'HorizontalAlignment', 'center')
%%




% SNODAS GRID
latlim = [43 44.5]; lonlim = [-116.3 -114.3]; % BRBlimits
Iy=find(lat2>=latlim(1) & lat2<=latlim(2)); % index to SNODAS pixels
Ix=find(lon2>=lonlim(1) & lon2<=lonlim(2));
lat2=lat2(Iy);lon2=lon2(Ix); SWE2=SWE2(Iy,Ix);
[LON2,LAT2]=meshgrid(lon2,lat2);
% GET ELEVATIONS FOR EACH GRID POINT
load BRBortho
latlim = [43 44.5]; lonlim = [-116.3 -114.3]; % original limts when downloaded (commented above)
[n3,m3]=size(Z);
latO=linspace(latlim(2),latlim(1),n3);
lonO=linspace(lonlim(1),lonlim(2),m3);
[LONO,LATO]=meshgrid(lonO,latO); % matricies for interpolation
Z2=interp2(LONO,LATO,Z,LON2,LAT2);

%%
hfig=figure(3);clf
set(hfig,'position',[1 43 1440 763])
%latlim=[43.2 44.4]; lonlim=[-116.3 -114.45];
P8{1}=[0.06 0.05 0.4 0.98]; P8{2}=[0.52 0.05 0.4 0.98];

%St={'Boise River Basin Ortho','Boise River Basin DEM'}

h8=subplot(1,2,1);
set(h8,'Position',P8{1})
ga=usamap(latlim,lonlim);
geoshow(LAT2,LON2,Z2,'DisplayType','surface','CData',Z2); colorbar
h8=subplot(1,2,2);
set(h8,'Position',P8{2})
ga=usamap(latlim,lonlim);
geoshow(LAT2,LON2,SWE2,'DisplayType','surface','CData',SWE2); colorbar
%view(3)
%%imagesc(lon2,lat2,SWE2,[100 800]); set(gca,'Ydir','normal'); colorbar

%%

%plotBRBmap(lat2,lon2,SWE2)
%%
%demcmap(SWE2)

