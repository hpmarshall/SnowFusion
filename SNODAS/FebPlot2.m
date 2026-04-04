r2=kml2struct('IdahoSNOTEL.kml')
BB=[-117 -114 42 45];
Lat=[r2(:).Lat];
Lon=[r2(:).Lon];
Ix=find(Lon>BB(1) & Lon<BB(2) & Lat>BB(3) & Lat<BB(4));
r3=r2(Ix);
filename='2014/02_Feb/S2014-2-8'
h=plotSNODASvar2(filename,r3)