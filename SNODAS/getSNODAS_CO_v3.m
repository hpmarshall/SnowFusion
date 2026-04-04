% this script downloads SNODAS data 
%% first set up the grid
lonmin=-124.733749999999;
lonmax=-66.9420833333342;
latmin=24.9495833333335;
latmax=52.8745833333323;
lon=linspace(lonmin,lonmax,6935);
lat=linspace(latmax,latmin,3351);
BB=[-106.9337 -105.9337 40.3087 40.6004];
Ix=find(lon>BB(1) & lon<BB(2));
Iy=find(lat>BB(3) & lat<BB(4));

%% now download SNODAS data
mw=ftp('sidads.colorado.edu','anonymous','hpmarshall@boisestate.edu');
cd(mw,'/DATASETS/NOAA/G02158/masked/')
D=dir(mw);
%%

%%
S={'1025SlL00','1025SlL01','1034','1036','1038','1039','1044','1050'}; % product code
S2={'Precip','SnowPrecip','SWE','Depth','Tsnow','SublimationBS','Melt','Sublimation'};
MI=zeros(length(Iy),length(Ix),365);
for n=1:length(S2)
    Snodas(1).(S2{n})=MI*NaN; % initialize each output
    Snodas(2).(S2{n})=MI*NaN; % initialize each output
end

%for n=4:5 %:length(mw)
%%
cd('TEMP'); % move to temp directory
nY=1;
%%
for n=4:5; % loop over year
    q=1;
    D(n).name
    cd(mw,['/DATASETS/NOAA/G02158/masked/' D(n).name]);
    Snodas(nY).year=D(n).name;
    dm=dir(mw);
    for m=1:length(dm) % loop over month
        Smonth=dm(m).name
        cd(mw,Smonth);
        d3=dir(mw,'*.tar');
        for p=1:length(d3) % loop over day
            mget(mw,d3(p).name);
            untar(d3(p).name);
            for p2=1:length(S)
                Dt=dir(['*' S{p2} '*.dat.gz']); % get the file for field q
                if ~isempty(Dt)
                    gunzip([Dt(1).name]); % unzip it
                    delete(Dt(1).name);
                    Dt=dir(['*' S{p2} '*.dat']);
                    fid=fopen(Dt(1).name); % open
                    D3=fread(fid,[6935 3351],'int16','b'); % read file
                    D3=D3'; % transpose result
                    Snodas(nY).(S2{p2})(:,:,q)=D3(Iy,Ix); % get area of interest
                    fclose(fid);
                    delete(Dt(1).name); % delete file
                end
            end
            delete(d3(p).name); % delete tar
            delete('*.gz');
            dd=d3(p).name(end-5:end-4); % get day of month from file
            S3=[dd '-' dd '-' Snodas(nY).year];
            Snodas(nY).date(q)=datenum(S3);
            q=q+1
        end
        cd(mw,'..');
    end  
    % convert all mass to units of [m]
    Snodas(nY).Precip=Snodas(nY).Precip(:,:,1:q-1)/1000/10; % put in [m]
    Snodas(nY).SnowPrecip=Snodas(nY).SnowPrecip(:,:,1:q-1)/1000/10; % snow accumulation [m WE]
    Snodas(nY).SWE=Snodas(nY).SWE(:,:,1:q-1)/1000; % [m] SWE
    Snodas(nY).Depth=Snodas(nY).Depth(:,:,1:q-1)/1000; % [m] Depth
    Snodas(nY).Tsnow=Snodas(nY).Tsnow(:,:,1:q-1)/1000; % [m] Depth
    Snodas(nY).SublimationBS=Snodas(nY).SublimationBS(:,:,1:q-1)/1e5; % [m] sublimation from blowing snow
    Snodas(nY).Sublimation=Snodas(nY).Sublimation(:,:,1:q-1)/1e5; % [m] sublimation from snowpack
    Snodas(nY).Melt=Snodas(nY).Melt(:,:,1:q-1)/1e5; % [m] melt
    nY=nY+1;
end

disp('finished, now saving...')
save SNODAS_CO_200607 Snodas

% ax=utmzone('11T');
% Ix=find(lon>ax(3) & lon<ax(4));
% Iy=find(lat>ax(1) & lat<ax(2));
% lat=lat(Iy);lon=lon(Ix);
% % lets convert this to UTM
% mstruct = defaultm('utm');
% mstruct.zone = '11T';
% mstruct = defaultm(mstruct);
% [LON,LAT]=meshgrid(lon,lat);
% [X,Y] = mfwdtran(mstruct,LAT,LON);
% %% now load boise basin shape file
% %[S,A]=shaperead('BRB_outline.shp');
%x2=min(S.X):1000:max(S.X); 
%y2=min(S.Y):1000:max(S.Y);
%[X2,Y2]=meshgrid(x2,y2);

