function plotKML(filename,Z,R)
% reads KML file and plots on map in 3D
%filename;
r5=kml_shapefile(filename);
for n=1:length(r5)
    Sz3=ltln2val(Z,R,r5(n).Y,r5(n).X);
    r5(n).Y=[r5(n).Y;r5(n).Y(1)];
    r5(n).X=[r5(n).X;r5(n).X(1)];
    Sz3=[Sz3;Sz3(1)];
    plot3m(r5(n).Y,r5(n).X,Sz3+100,'w','LineWidth',3)
end