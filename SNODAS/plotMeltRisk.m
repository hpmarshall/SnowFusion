% plotMeltRisk
load MarGM_15yrs.mat
[LON,LAT]=meshgrid(lon,lat);
latlim=[38.8 39.2]; lonlim=[-108.4 -107.6]; % set region of interest
%St=MarSWE2(:,:,15);
St=MarTemp2(:,:,15)*10;
zlim=[265 273.15];
%zlim=[min(St(:)) max(St(:))];
hG=plotSNODASvar9_v2(LAT,LON,St,latlim,lonlim,zlim);
%% pdf of SWE
Ix=find(lon>-108.2 & lon<107.8);
Iy=find(lat>39.0 & lat<39.1);
%St2=St(Iy,Ix);
St2=MarTemp2(Iy,Ix,:)*10;
figure(4);clf
xbins=250:280;
hist(St2(:),xbins)