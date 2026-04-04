% this script downloads SNODAS data 
%% first set up the grid
lonmin=-124.733749999999;
lonmax=-66.9420833333342;
latmin=24.9495833333335;
latmax=52.8745833333323;
lon=linspace(lonmin,lonmax,6935);
lat=linspace(latmax,latmin,3351);
ax=utmzone('11T');
Ix=find(lon>ax(3) & lon<ax(4));
Iy=find(lat>ax(1) & lat<ax(2));
lat=lat(Iy);lon=lon(Ix);
% lets convert this to UTM
mstruct = defaultm('utm');
mstruct.zone = '11T';
mstruct = defaultm(mstruct);
[LON,LAT]=meshgrid(lon,lat);
[X,Y] = mfwdtran(mstruct,LAT,LON);
%% now load boise basin shape file
[S,A]=shaperead('BRB_outline.shp');
x2=min(S.X):1000:max(S.X); 
y2=min(S.Y):1000:max(S.Y);
[X2,Y2]=meshgrid(x2,y2);

%% now download SNODAS data
mw=ftp('sidads.colorado.edu','anonymous','hpmarshall@boisestate.edu')
cd(mw,'/DATASETS/NOAA/G02158/masked/')
D=dir(mw);
D2=zeros(98,117,4092);
q=1;
%%
for n=1:11 %:length(mw)
    cd(mw,['/DATASETS/NOAA/G02158/masked/' D(n).name])
    dm=dir(mw);
    for m=1:length(dm)
        Smonth=dm(m).name
        cd(mw,Smonth);
        d3=dir(mw,'*.tar');
        tic
        for p=1:length(d3)
                cd('TEMP');
                mget(mw,d3(p).name);
                untar(d3(p).name);
                Dt=dir(['us_ssmv11034*.dat.gz']);
                gunzip([Dt.name]);
                Dt=dir(['us_ssmv11034*.dat']);
                delete('*.gz','*.tar');
                cd ..
                D2(:,:,q) = loadSNODAS_BB(['TEMP/' Dt.name],Ix,Iy,X,Y,X2,Y2);
                S2{q,1}=[Smonth '-' num2str(p)];
                q=q+1;
                movefile('TEMP/*.dat','SWE2013');
        end
        toc
        cd(mw,'..');
    end
end