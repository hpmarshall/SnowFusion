% plotSNODAS_CO.m
load('SNODAS_CO200607.mat')
%
for n=1:length(Snodas(1).date)
    n
    date06(n)=datenum([Snodas(1).date{n}(4:end) '-2006'],'mmm-dd-yyyy');
end
for n2=1:length(Snodas(2).date)
    n2
    date07(n2)=datenum([Snodas(2).date{n2}(4:end) '-2007'],'mmm-dd-yyyy');
end
clear Snodas
load('SNODAS_CO_200607')
rmfield(Snodas,'date')
Snodas(1).date=date06;
Snodas(2).date=date07;

%%
lonmin=-124.733749999999;
lonmax=-66.9420833333342;
latmin=24.9495833333335;
latmax=52.8745833333323;
lon=linspace(lonmin,lonmax,6935);
lat=linspace(latmax,latmin,3351);
BB=[-106.9337 -105.9337 40.3087 40.6004]; % bounding box
Ix=find(lon>BB(1) & lon<BB(2));
Iy=find(lat>BB(3) & lat<BB(4));
Snodas(1).lat=lat(Iy);
Snodas(1).lon=lon(Ix);
Snodas(2).lat=lat(Iy);
Snodas(2).lon=lon(Ix);

%% get UTM coordinates
myUTM=utmzone(Snodas(1).lat(1,end),Snodas(1).lon(1,end)); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);
[LON,LAT]=meshgrid(Snodas(1).lon,Snodas(1).lat);
[X,Y] = mfwdtran(mstruct,LAT,LON);
x=(X(1,:)-337338)/1000; y=(Y(:,1)-4463901)/1000; % x/y coor for plot

%% lets make an image of melt
dateIOP1=datenum('3-Dec-2006'); % date of IOP1 flight
dateIOP2=datenum('22-Feb-2007');
I2=find(Snodas(1).date>=dateIOP1); % index to images in 2006
I3=find(Snodas(2).date<=dateIOP2); % index to images in 2007
%% first lets plot total input, total output
SubAllBS=cat(3,Snodas(1).SublimationBS(:,:,I2),Snodas(2).SublimationBS(:,:,I3)); % concatinate 
SubAll=cat(3,Snodas(1).Sublimation(:,:,I2),Snodas(2).Sublimation(:,:,I3)); % concatinate 
SubTot=sum(SubAllBS,3)+sum(SubAll,3); % sum all the sublimation loss
MeltAll=cat(3,Snodas(1).Melt(:,:,I2),Snodas(2).Melt(:,:,I3)); % concatinate the melt from 06/07
MeltTot=sum(MeltAll,3); % sum all the melt
PrecipAll=cat(3,Snodas(1).Precip(:,:,I2),Snodas(2).Precip(:,:,I3)); % concatinate the precip from 06/07
PrecipTot=sum(PrecipAll,3); % sum all rain
SnowPrecipAll=cat(3,Snodas(1).SnowPrecip(:,:,I2),Snodas(2).SnowPrecip(:,:,I3)); % concatinate the snow precip from 06/07
SnowPrecipTot=sum(SnowPrecipAll,3); % sum all the melt
% modeled bulk totals
SWEAll=cat(3,Snodas(1).SWE(:,:,I2),Snodas(2).SWE(:,:,I3)); % concatinate the SWE from 06/07
dSWE=SWEAll(:,:,end)-SWEAll(:,:,1); % SWE difference
DepthAll=cat(3,Snodas(1).Depth(:,:,I2),Snodas(2).Depth(:,:,I3)); % concatinate the depths from 06/07
dDepth=DepthAll(:,:,end)-DepthAll(:,:,1); % SWE difference

%% first input/output
figure(1);clf; subplot(2,2,1)
imagesc(x,y,MeltTot*100); colorbar; set(gca,'YDir','normal'); title('Total Melt [cm]')
subplot(2,2,2)
imagesc(x,y,-SubTot*100); colorbar; set(gca,'YDir','normal'); title('Total Sublimation [cm]')
subplot(2,2,3)
imagesc(x,y,PrecipTot*100); colorbar; set(gca,'YDir','normal'); title('Total Rain [cm]')
subplot(2,2,4)
imagesc(x,y,SnowPrecipTot*100); colorbar; set(gca,'YDir','normal'); title('Total Snow [cm]')
%%
figure(2);clf; subplot(2,2,1)
imagesc(x,y,dSWE*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('change in SWE [cm]')
subplot(2,2,2)
imagesc(x,y,dDepth*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('change in depth [cm]')
subplot(2,2,3)
imagesc(x,y,-SubTot./dSWE*100,[0 100]); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Melt % of dSWE')
subplot(2,2,4)
imagesc(x,y,(MeltTot)./dSWE*100,[0 100]); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('(Melt+Sub) % of dSWE')
%% 







%% units for each
% Precip = kg/m^2 div 10
% SnowAccum = kg/m^2 div 10
% SWE = m div 1000
% depth = m div 1000
% blowing snow sublimation = m div 100,000
% Melt = m div 100,000
% Sublimation = m div 100,000














