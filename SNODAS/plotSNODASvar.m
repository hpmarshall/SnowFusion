% plotSNODASvar
% HPM 02/15/14
% plots selected variable from SNODAS file
% INPUT: filename = name of mat file downloaded using getSNODASall
%            Svar = variable number

function h=plotSNODASvar(filename,Iz,maxz)

load(filename)
% get UTM coordinates
BB=[-117 -114 42 45];
Ix=find(lon>BB(1) & lon<BB(2));
Iy=find(lat>BB(3) & lat<BB(4));
myUTM=utmzone(mean(lat(Ix)),mean(lon(Iy))); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);
[LON,LAT]=meshgrid(lon(Iy),lat(Ix));
[X,Y] = mfwdtran(mstruct,LAT,LON);
x=X(1,:); y=Y(:,1);
%subplot(1,2,1)
SWE=r(Iz).data(Ix,Iy)';
I3=find(SWE<=0);
SWE(I3)=NaN;
h=imagesc(x,y,SWE,maxz); set(gca,'YDir','normal');
colorbar; set(gca,'YDir','normal','FontSize',14,'FontWeight','bold','LineWidth',3); 
title(r(Iz).name)
xlabel('UTM zone 11T Easting'); ylabel('UTM zone 11T Northing')
axis equal
axis tight
[S,A]=shaperead('BRB_outline.shp'); hold on
Amap=ones(size(SWE)); 
Amap(isnan(SWE))=0;
Amap(Amap==0)=0;
alpha(Amap)
plot(S.X,S.Y,'k-','LineWidth',3)
%[S5,A]=shaperead('rcew_boundary_nad83.shp'); hold on
%for n=1:length(S5)
%    plot(S5(n).X,S5(n).Y,'k-','LineWidth',3)
%end
axis([5.71e5 7.15e5 4.78e6 4.91e6])
%subplot(1,2,2)
%hist(SWE(:),200)