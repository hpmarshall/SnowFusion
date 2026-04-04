% plotSNODAS
D3=D2(:,:,1);
Amap=ones(size(D3)); Amap(isnan(D3))=0;
figure(3);clf
h=imagesc(x2,y2,D3); set(gca,'YDir','normal'); hold on
alpha(Amap)
plot(S.X,S.Y,'k-','LineWidth',3)
set(gca,'FontSize',14,'FontWeight','bold')
xlabel('UTM Easting [m]')
ylabel('UTM Northing [m]')
title('Boise River Basin')
[lat,lon,z]=read_kml('IdahoSNOTEL.kml');