function D2 = loadSNODAS_BB(filename,Ix,Iy,X,Y,Xi,Yi)

fid=fopen(filename);
D=fread(fid,[6935 3351],'int16','b');
D=D'/1000;
D=D(Iy,Ix); % subset of SNODAS output for idaho
F=scatteredInterpolant(X(:),Y(:),D(:),'linear'); % fit surface
D2=F(Xi,Yi);
Ix=find(D2<=0.001);
D2(Ix)=NaN;
% %%
% lonmin=-124.733749999999;
% lonmax=-66.9420833333342;
% latmin=24.9495833333335;
% latmax=52.8745833333323;
% lon=linspace(lonmin,lonmax,6935);
% lat=linspace(latmax,latmin,3351);
% %%
% ax=utmzone('11T');
% Ix=find(lon>ax(3) & lon<ax(4));
% Iy=find(lat>ax(1) & lat<ax(2));
% D=D(Iy,Ix); % subset of SNODAS output for idaho
% lat=lat(Iy);lon=lon(Ix);
% 
% %% lets convert this to UTM
% mstruct = defaultm('utm');
% mstruct.zone = '11T';
% mstruct = defaultm(mstruct);
% [LON,LAT]=meshgrid(lon,lat);
% [X,Y] = mfwdtran(mstruct,LAT,LON);
% %% now interpolate to regular grid
% F=scatteredInterpolant(X(:),Y(:),D(:),'linear'); % fit surface
% %% now load boise basin shape file
% [S,A]=shaperead('BRB_outline.shp');
% %%
% x2=min(S.X):1000:max(S.X); % 
% y2=min(S.Y):1000:max(S.Y);
% [X2,Y2]=meshgrid(x2,y2);
% D2=F(X2,Y2);
% Ix=find(D2<=0.001);
% D2(Ix)=NaN; % set values less than 1mm to NaN
% %Amap=ones(size(D2)); Amap(isnan(Amap))=0;
% %%
% %figure(3);clf
% %h=imagesc(x2,y2,D2); set(gca,'YDir','normal'); hold on
% %alpha(Amap)
% %plot(S.X,S.Y,'r-','LineWidth',3)