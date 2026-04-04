function makeSNODASmovie(movieFile,lat,lon,S)




hfig=figure('Renderer','opengl')
set(hfig,'position',[1 35 1280 671]) 
[i2,j2]=size(S); subplot(i2,j2,1);




G=plotSNODAS10(lat,lon,S{1,1})
%hG=textm(43.3,-116,300,['Feb 1, 2014'],'FontSize',18,'FontWeight','bold','Color','w') hs=subplot(1,2,2); set(hs,'position',[0.5 0 0.5 1])
%G2=plotSNODAS9(Sfiles{1},3)
%hG2=textm(43.3,-116,300,['Feb 1, 2014'],'FontSize',18,'FontWeight','bold','Color','w') 


%%

% now make movie
writerObj = VideoWriter(movieFile);
open(writerObj);
for n=1:length(Sfiles)
    R=load(Sfiles{n})
    set(G,'cdata',SWE,'alphadata',Amap);
    set(hG,'String',['Feb ' num2str(n) ', 2014']);
    drawnow
    SnowP=R.r(3).data(Ix,Iy)'; SnowP=full(SnowP);
    Amap2=ones(size(SnowP)); Amap2(SnowP==0)=0;
    set(G2,'cdata',SnowP,'alphadata',Amap2);
    set(hG2,'String',['Feb ' num2str(n) ', 2014']);
    drawnow
    M(n)=getframe(hfig);
    %writeVideo(writerObj,M(n));
end
writeVideo(writerObj,M)
close(writerObj)

function G=plotSNODAS10(lat,lon,St)


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