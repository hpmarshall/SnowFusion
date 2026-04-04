function [latk,lonk]=plotKML2(filename)
% reads KML file and plots on map in 3D
filename
r5=kml_shapefile(filename);
Xall=[];Yall=[];
for n=1:length(r5)
    plot3m(r5(n).Y,r5(n).X,100*ones(size(r5(n).Y)),'w','LineWidth',3)
    Xall=[Xall;r5(n).X(:)];
    Yall=[Yall;r5(n).Y(:)];
end
latk=nanmean(Yall);
lonk=nanmean(Xall);
