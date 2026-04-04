% getDEMortho
% ortho = wmsfind('SDDS_Imagery', 'SearchField', 'serverurl'); 
% ortho = refine(ortho,  'Orthoimagery','SearchField', 'serverurl'); 
% layers = wmsfind('nasa.network', 'SearchField', 'serverurl');
% us_ned = layers.refine('usgs ned 30');
% latlim = [43 44.5];
% lonlim = [-116.3 -114.3];
% samplesPerInterval = dms2degrees([0 0 5]);
% imageHeight = 5000;
% imageWidth = 5000;
% A = wmsread(ortho, 'Latlim', latlim, 'Lonlim', lonlim, ...
%    'CellSize', samplesPerInterval);
% [Z, R] = wmsread(us_ned, 'ImageFormat', 'image/bil', ...
%     'Latlim', latlim, 'Lonlim', lonlim, ...
%     'CellSize', samplesPerInterval);
% Z=double(Z);
% save BRBortho
load BRBortho
set(0,'DefaultLineLineWidth',2)
set(0,'DefaultTextFontSize',14)
set(0,'DefaultTextFontWeight','bold')
set(0,'DefaultAxesFontSize',14)
set(0,'DefaultAxesFontWeight','bold')
set(0,'DefaultAxesLineWidth',2)
set(0,'DefaultLineMarkerSize',12)
set(0,'DefaultAxesFontWeight','bold')
set(0,'DefaultAxesFontName','FixedWidth')
set(0,'DefaultAxesFontSize',14)
set(0,'FixedWidthFontName','Times')

hfig=figure('Renderer','opengl')
set(hfig,'position',[1 35 1280 671])
latlim=[43.2 44.4]; lonlim=[-116.2 -114.6];
R=load('2014/03_Mar/S2014-3-13.mat');
Iy=find(R.lat>latlim(1) & R.lat<latlim(2));
Ix=find(R.lon>lonlim(1) & R.lon<lonlim(2));
lon=R.lon(Ix); lat=R.lat(Iy);
SWE=R.r(4).data(Ix,Iy)'; SWE=full(SWE);
[LON,LAT]=meshgrid(lon,lat);
h8=subplot(1,1,1)
set(h8,'Position',[0.05 0.05 0.9 0.9])
ga=usamap(latlim, lonlim);
%setm(ga,'LineWidth',3,'FontSize',14,'FontWeight','bold')
%framem off; mlabel off; plabel off; gridm off
Amap=ones(size(SWE)); Amap(SWE<=10)=0;
%z=zeros(size(SWE));
G=geoshow(LAT,LON,SWE,'displaytype','texturemap');
set(G,'facecolor','texturemap','cdata',SWE);
set(G,'edgecolor','none','facealpha','texture','alphadata',Amap);
set(G,'backfacelighting','unlit');
setm(ga,'FontSize',16,'FontWeight','bold')

%%
hold on
[S,A2]=shaperead('BRB_outline.shp');
myUTM=utmzone(mean(latlim),mean(lonlim)); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);
[S.lat,S.lon] = minvtran(mstruct,S.X,S.Y);
plot3m(S.lat,S.lon,100*ones(size(S.lat)),'w','linewidth',4)

%% add HW21 Lidar area
[latk,lonk]=plotKML2('HW21.kml')
textm(latk,lonk,200,'HW21','FontSize',16,'FontWeight','bold','Color','k')
[latk,lonk]=plotKML2('DryCreekBoundary.kml');
textm(latk,lonk,200,'DCEW','FontSize',16,'FontWeight','bold','Color','k')

%% now plot SNOTELs
r2=kml2struct('IdahoSNOTEL.kml')
BB=[lonlim latlim];
Lat=[r2(:).Lat];
Lon=[r2(:).Lon];
Ix=find(Lon>BB(1) & Lon<BB(2) & Lat>BB(3) & Lat<BB(4));
r3=r2(Ix);
for n=1:length(r3)
    plotm(r3(n).Lat,r3(n).Lon,'k+','LineWidth',3,'MarkerSize',8)
    textm(r3(n).Lat+0.01,r3(n).Lon+0.01,200,r3(n).Name,'FontSize',16,'FontWeight','bold','Color','w')
end