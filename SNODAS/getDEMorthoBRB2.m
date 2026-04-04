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
hfig=figure('Renderer','opengl')
set(hfig,'position',[1 35 1280 671])
latlim=[43.2 44.4]; lonlim=[-116.2 -114.6];
P8{1}=[0 0 0.5 1]; P8{2}=[0.5 0 0.5 1];
%St={'Boise River Basin Ortho','Boise River Basin DEM'}
for n8=1:2
    h8=subplot(1,2,n8)
    set(h8,'Position',P8{n8})
ga=usamap(latlim,lonlim)
%framem off; mlabel off; plabel off; gridm off
if n8<2
    geoshow(Z, R, 'DisplayType', 'surface', 'CData', A);
else
    geoshow(Z, R, 'DisplayType', 'surface', 'CData', Z); 
end
setm(ga,'FontSize',16,'FontWeight','bold')
hold on
[S,A2]=shaperead('BRB_outline.shp');
myUTM=utmzone(mean(latlim),mean(lonlim)); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);
[S.lat,S.lon] = minvtran(mstruct,S.X,S.Y);
[S.Z,ri,S.lat,S.lon]=mapprofile(Z,R,S.lat,S.lon);
plot3m(S.lat,S.lon,S.Z,'r','linewidth',3)

%% add HW21 Lidar area
plotKML('HW21.kml',Z,R)
plotKML('DryCreekBoundary.kml',Z,R);


%% now plot SNOTELs
r2=kml2struct('IdahoSNOTEL.kml')
BB=[lonlim latlim];
Lat=[r2(:).Lat];
Lon=[r2(:).Lon];
Ix=find(Lon>BB(1) & Lon<BB(2) & Lat>BB(3) & Lat<BB(4));
r3=r2(Ix);
hst=[];
for n=1:length(r3)
    Sz=ltln2val(Z,R,r3(n).Lat,r3(n).Lon);
    plot3m(r3(n).Lat,r3(n).Lon,Sz+50,'r+','LineWidth',3,'MarkerSize',8)
    hst(n)=textm(r3(n).Lat+0.01,r3(n).Lon+0.01,Sz+1000,r3(n).Name,'FontSize',14,'FontWeight','bold')
end
if n8>1
    set(hst,'Color','k')
else
    set(hst,'Color','w')
end
%title(St{n8})
end