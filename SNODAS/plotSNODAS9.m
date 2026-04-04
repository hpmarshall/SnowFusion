function G=plotSNODAS9(SNODASfile,myvar)

load BRBortho
%hfig=figure('Renderer','opengl')
%set(hfig,'position',[1 35 1280 671])
latlim=[43.2 44.4]; lonlim=[-116.2 -114.6];
R=load(SNODASfile);
Iy=find(R.lat>latlim(1) & R.lat<latlim(2));
Ix=find(R.lon>lonlim(1) & R.lon<lonlim(2));
lon=R.lon(Ix); lat=R.lat(Iy);
SWE=R.r(myvar).data(Ix,Iy)'; SWE=full(SWE);
[LON,LAT]=meshgrid(lon,lat);
%h8=subplot(1,1,1)
%set(h8,'Position',[0.05 0.05 0.9 0.9])
ga=usamap(latlim, lonlim);
set(gca,'nextplot','replacechildren');
%setm(ga,'LineWidth',3,'FontSize',14,'FontWeight','bold')
%framem off; mlabel off; plabel off; gridm off
Amap=ones(size(SWE)); Amap(SWE<=0)=0;
%z=zeros(size(SWE));
G=geoshow(LAT,LON,SWE,'displaytype','texturemap'); colorbar('location','north')
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
textm(latk,lonk,200,'HW21','FontSize',16,'FontWeight','bold','Color','w')
[latk,lonk]=plotKML2('DryCreekBoundary.kml');
textm(latk,lonk,200,'DCEW','FontSize',16,'FontWeight','bold','Color','w')

%% now plot SNOTELs
r2=kml2struct('IdahoSNOTEL.kml')
BB=[lonlim latlim];
Lat=[r2(:).Lat];
Lon=[r2(:).Lon];
Ix=find(Lon>BB(1) & Lon<BB(2) & Lat>BB(3) & Lat<BB(4));
r3=r2(Ix);
for n=1:length(r3)
    plotm(r3(n).Lat,r3(n).Lon,'k+','LineWidth',3,'MarkerSize',8)
    textm(r3(n).Lat+0.01,r3(n).Lon+0.01,200,r3(n).Name(1),'FontSize',18,'FontWeight','bold','Color','w')
end