% plotSNODAS_CO.m
load('TEMP/SNODAS_2009_RME')
%%
S={'1025SlL00','1025SlL01','1034','1036','1038','1039','1044','1050'}; % product code
S2={'Precip','SnowPrecip','SWE','Depth','Tsnow','SublimationBS','Melt','Sublimation'};


%% get UTM coordinates
BB=[-117 -114 42 45];
lonmin=-124.733749999999;
lonmax=-66.9420833333342;
latmin=24.9495833333335;
latmax=52.8745833333323;
lon=linspace(lonmin,lonmax,6935);
lat=linspace(latmax,latmin,3351);
Ix=find(lon>BB(1) & lon<BB(2));
Iy=find(lat>BB(3) & lat<BB(4));
Snodas(1).lon=lon(Ix); Snodas(1).lat=lat(Iy);
myUTM=utmzone(mean(lat(Ix)),mean(lon(Iy))); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);
[LON,LAT]=meshgrid(Snodas(1).lon,Snodas(1).lat);
[X,Y] = mfwdtran(mstruct,LAT,LON);
x=X(1,:); y=Y(:,1);
%x=(X(1,:)-337338)/1000; y=(Y(:,1)-4463901)/1000; % x/y coor for plot

% % first lets plot total input, total output
% SubTot=Snodas.Sublimation+SubAll; % sum all the sublimation loss
% MeltTot=Snodas.Melt; % sum all the melt
% SnowPrecipAll=cat(3,Snodas(1).SnowPrecip(:,:,I2),Snodas(2).SnowPrecip(:,:,I3)); % concatinate the snow precip from 06/07
% SnowPrecipTot=sum(SnowPrecipAll,3); % sum all the melt
% modeled bulk totals
% SWEAll=cat(3,Snodas(1).SWE(:,:,I2),Snodas(2).SWE(:,:,I3)); % concatinate the SWE from 06/07
% dSWE=SWEAll(:,:,end)-SWEAll(:,:,1); % SWE difference
% DepthAll=cat(3,Snodas(1).Depth(:,:,I2),Snodas(2).Depth(:,:,I3)); % concatinate the depths from 06/07
% dDepth=DepthAll(:,:,end)-DepthAll(:,:,1); % SWE difference

%% first input/output
hfig=figure(1);clf; subplot(1,2,1) 
set(hfig,'position',[1 35 1280 671])
SWE=Snodas.SWE(Iy,Ix);
I3=find(SWE<0);
SWE(I3)=NaN;
h=imagesc(x,y,SWE*100,[0 30]); set(gca,'YDir','normal');
colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); 
title('March 19, 2009 SNODAS SWE [cm]')
xlabel('UTM zone 11T Easting'); ylabel('UTM zone 11T Northing')
axis equal
axis tight
[S,A]=shaperead('BRB_outline.shp'); hold on
Amap=ones(size(SWE)); 
Amap(isnan(SWE))=0;
alpha(Amap)
plot(S.X,S.Y,'w-','LineWidth',3)
[S5,A]=shaperead('rcew_boundary_nad83.shp'); hold on
for n=1:length(S5)
    plot(S5(n).X,S5(n).Y,'w-','LineWidth',3)
end
subplot(1,2,2)
h=imagesc(x,y,SWE*100,[0 100]); set(gca,'YDir','normal');
colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); 
title('March 19, 2009 SNODAS SWE [cm]')
xlabel('UTM zone 11T Easting'); ylabel('UTM zone 11T Northing')
axis equal
axis tight
[S,A]=shaperead('BRB_outline.shp'); hold on
Amap=ones(size(SWE)); 
Amap(isnan(SWE))=0;
alpha(Amap)
plot(S.X,S.Y,'w-','LineWidth',3)
axis([min(S.X)-5000 max(S.X)+5000 min(S.Y)-10000 max(S.Y)+100000])


%
















