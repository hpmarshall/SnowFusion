% plotSNODAS_CO.m
load('SNODAS_CO_200607')
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
imagesc(x,y,MeltTot*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Total Melt [cm]')
xlabel('False Easting'); ylabel('False Northing')
subplot(2,2,2)
imagesc(x,y,-SubTot*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Total Sublimation [cm]')
xlabel('False Easting'); ylabel('False Northing')
subplot(2,2,4)
imagesc(x,y,-SubTot./SnowPrecipTot*100,[0 100]); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Sublimation % of Snow Precip')
xlabel('False Easting'); ylabel('False Northing')
subplot(2,2,3)
imagesc(x,y,MeltTot./SnowPrecipTot*100,[0 50]); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Melt % of Snow Precip')
xlabel('False Easting'); ylabel('False Northing')
print -dpng SNODASmeltSub.png
%
figure(2);clf; subplot(2,2,1)
imagesc(x,y,dSWE*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('change in SWE [cm]')
xlabel('False Easting'); ylabel('False Northing')
subplot(2,2,2)
imagesc(x,y,dDepth*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('change in depth [cm]')
xlabel('False Easting'); ylabel('False Northing')
subplot(2,2,4)
imagesc(x,y,PrecipTot*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Total Rain Precip [cm]')
xlabel('False Easting'); ylabel('False Northing')
subplot(2,2,3)
imagesc(x,y,SnowPrecipTot*100); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Total Snow Precip (w.e.) [cm]')
xlabel('False Easting'); ylabel('False Northing')
print -dpng SNODASinputBulk.png
% 
figure(3);clf
imagesc(x,y,MeltTot./SnowPrecipTot*100,[0 50]); colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); title('Melt % of Snow Precip')
xlabel('False Easting'); ylabel('False Northing')
print -dpng Melt.png






%% units for each
% Precip = kg/m^2 div 10
% SnowAccum = kg/m^2 div 10
% SWE = m div 1000
% depth = m div 1000
% blowing snow sublimation = m div 100,000
% Melt = m div 100,000
% Sublimation = m div 100,000














