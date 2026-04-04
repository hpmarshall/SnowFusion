% getDEMorthoGM
% ortho = wmsfind('SDDS_Imagery', 'SearchField', 'serverurl'); 
% ortho = refine(ortho,  'Orthoimagery','SearchField', 'serverurl'); 
% layers = wmsfind('nasa.network', 'SearchField', 'serverurl');
% us_ned = layers.refine('usgs ned 30');
% latlim = [37 39];
% lonlim = [-108.5 -107];
% samplesPerInterval = dms2degrees([0 0 5]);
% imageHeight = 5000;
% imageWidth = 5000;
% A = wmsread(ortho, 'Latlim', latlim, 'Lonlim', lonlim, ...
%    'CellSize', samplesPerInterval);
% [Z, R] = wmsread(us_ned, 'ImageFormat', 'image/bil', ...
%     'Latlim', latlim, 'Lonlim', lonlim, ...
%     'CellSize', samplesPerInterval);
% Z=double(Z);

%%
load SWcolorado
figure('Renderer','opengl')
usamap(latlim, lonlim)
framem off; mlabel off; plabel off; gridm off
geoshow(Z, R, 'DisplayType', 'surface', 'CData', A);
daspectm('m',3)
lighting phong

%%
%view(3)
% plot BRB outline
hold on
%[S,A]=shaperead('BRB_outline.shp');
myUTM=utmzone(mean(latlim),mean(lonlim)); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);

%% SNOTEL
r=kml2struct('Colorado.kml');
for n=1:length(r)
    z=ltln2val(Z,R,r(n).Lat,r(n).Lon);
    plot3m(r(n).Lat,r(n).Lon,z(n)+50,'y^','LineWidth',4,'MarkerSize',6)
    textm(r(n).Lat,r(n).Lon,z(n)+50,'Color','r','FontSize',10)
end




%% Mesowest Stations/SNOTEL



% [D,MWS]=xlsread('MESOWEST_CO.xls');
% 
% 
% Ix=find(D(:,1)>latlim(1) & D(:,1)<latlim(2) & D(:,2)>lonlim(1) & D(:,2)<lonlim(2));
% D=D(Ix,:);
% T=MWS(Ix,7);
% S=MWS(Ix,2);
% D(:,3)=ltln2val(Z,R,D(:,1),D(:,2));
% plot3m(D(:,1),D(:,2),D(:,3)+50,'y^','LineWidth',4,'MarkerSize',6)
% s=MWS(Ix,:);
% for n=1:length(D)
%     textm(D(n,1),D(n,2),D(n,3)+5000,s{n},'Color','r','FontSize',10);
% end
% 
% %%
% t=strfind(T,'SNOTEL');
% SIx=[];
% %%
% for n=1:length(t)
%     t2=t(n);
%     t2=t2{:};
%     if ~isempty(t2)
%          plot3m(D(n,1),D(n,2),D(n,3)+50,'ro','LineWidth',3,'MarkerSize',8)
%          textm(D(n,1),D(n,2),D(n,3)+500,S{n},'Color','r','FontSize',10);
%          T{n}
%          S{n}
%          SIx=[SIx;n];
%     end
% end
% 
% 









%[S.lat,S.lon] = minvtran(mstruct,S.X,S.Y);
%[S.Z,ri,S.lat,S.lon]=mapprofile(Z,R,S.lat,S.lon);
%plot3m(S.lat,S.lon,S.Z,'r','linewidth',3)

%% add HW21 Lidar area
% plotKML('HW21.kml',Z,R)
% plotKML('DryCreekBoundary.kml',Z,R);
% plotKML('Stanley.kml',Z,R)
% plotKML('Bannock.kml',Z,R)
% plotKML('Sawtooth.kml',Z,R)
% plotKML('Bulltrout.kml',Z,R)

% %% plot all weather obs
% [D,MWS]=xlsread('MESOWEST_ID.xls');
% Ix=find(D(:,4)>latlim(1) & D(:,4)<latlim(2) & D(:,5)>lonlim(1) & D(:,5)<lonlim(2));
% for n=1:length(Ix)
%     Sz3=ltln2val(Z,R,D(Ix,4),D(Ix,5));
%     plot3m(D(Ix,4),D(Ix,5),Sz3+50,'yx','LineWidth',3,'MarkerSize',6)
% end
% 
% %% now plot SNOTELs
% r2=kml2struct('IdahoSNOTEL.kml')
% BB=[-108.5 -107.5 39 40];
% Lat=[r2(:).Lat];
% Lon=[r2(:).Lon];
% Ix=find(Lon>BB(1) & Lon<BB(2) & Lat>BB(3) & Lat<BB(4));
% r3=r2(Ix);
% for n=1:length(r3)
%     Sz=ltln2val(Z,R,r3(n).Lat,r3(n).Lon);
%     plot3m(r3(n).Lat,r3(n).Lon,Sz+50,'r+','LineWidth',3,'MarkerSize',8)
%     textm(r3(n).Lat+0.01,r3(n).Lon+0.01,Sz+500,r3(n).Name,'FontSize',10,'FontWeight','bold','Color','r')
% end