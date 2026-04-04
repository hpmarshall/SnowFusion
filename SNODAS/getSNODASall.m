% getSNODASall
% this script gets all SNODAS data from the archive

lonmin=-124.733749999999;
lonmax=-66.9420833333342;
latmin=24.9495833333335;
latmax=52.8745833333323;
lon=linspace(lonmin,lonmax,6935);
lat=linspace(latmax,latmin,3351);
mw=ftp('sidads.colorado.edu','anonymous','hpmarshall@boisestate.edu');
cd(mw,'/pub/DATASETS/NOAA/G02158/masked/')
%S={'1025SlL00','1025SlL01','1034','1036','1038','1039','1044','1050'}; % product code
%S={'us_ssmv01025SlL00','us_ssmv01025SlL01','us_ssmv11034tS__T','us_ssmv11036tS__T',...
%    'us_ssmv11038wS__A','us_ssmv11039lL00T','us_ssmv11044bS__T','us_ssmv11050lL00T'};

S={'1025SlL00','1025SlL01','1034','1036','1038','1039','1044','1050'}
S2={'Rainfall','Snowfall','SWE','Snow depth','Snow temp','Blowing snow sublimation','Snow melt','Snow pack sublimation'};



D=dir(mw); % get years
%% main loop
for n1=3:length(D) %loop over all years
    cd(['/Users/hpm/D_DRIVE/SNODAS/'])
    Syear=D(n1).name % current year
    mkdir(Syear); cd(Syear) % make local directory and enter
    cd(mw,['/pub/DATASETS/NOAA/G02158/masked/' Syear]); % enter remote directory
    dm=dir(mw); % get all months
    for n2=3:length(dm) % loop over month
        Smonth=dm(n2).name % current month
        if ~exist(Smonth,'dir')
            mkdir(Smonth); % make local directory
        end
        cd(Smonth) %
        cd(mw,Smonth) % enter remote month directory
        dd=dir(mw,'*.tar'); % get all days
        for n3=1:length(dd) % loop over day - 1 tar file for each
            Sday=dd(n3).name % current day
            date=[str2double(Syear) str2double(Smonth(1:2)) str2double(Sday(end-5:end-4))]; % [YYYY MM DD]
            matSNODAS=['S' num2str(date(1)) '-' num2str(date(2)) '-' num2str(date(3))];
            if ~exist([matSNODAS '.mat'],'file')
                try
                    mget(mw,Sday); % get the tar file
                    try
                        untar(Sday,'temp'); % untar it
                    catch
                        disp([Sday ' did not complete!'])
                    end
                    delete(Sday); % remove tar file
                    cd temp
                    dp=dir('*.dat.gz'); % get all zipped files, one for each parameter
                    %r=struct('name',S2);
                    for n4=1:length(dp)
                        Svar=dp(n4).name;
                        stemp=[];
                        for n5=1:length(S)
                            stemp(n5)=length(strfind(Svar,S{n5}));
                        end
                        Ix=find(stemp);
                        %Ix=find(strncmp(Svar,S,17)); % get index to state name
                        if length(Ix)
                            Sstate=S2{Ix}; % current variable
                        else
                            Sstate=[];
                        end
                        gunzip(Svar); % unzip it
                        delete(Svar); % remove gz
                        [~,Svar2]=fileparts(Svar); % get name of .dat file just unzipped
                        fid=fopen(Svar2); % open
                        D3=fread(fid,[6935 3351],'int16','b'); % read file
                        D3=D3'; % transpose matrix
                        D3(D3<0)=0; % set -9999 to 0
                        r(n4).name=Sstate;
                        r(n4).date=date;
                        r(n4).data=sparse(D3'); % transpose result and make sparse
                        delete(Svar2); % remove dat file
                        clear D3
                        fclose(fid);
                    end
                    delete('*.gz')
                    delete('*.dat')
                    cd ..
                    save(matSNODAS,'r','lat','lon')
                    delete('*.gz') % remove all gz files (headers)
                    clear r
                catch
                    disp(['file:' Sday ' not on server, skipping...'])
                end
            end
        end
        cd .. % back out of month directory - local
        cd(mw,'..') % back out of month - remote
    end
    cd .. % back out of year directory
    cd(mw,'..') % back out of year - remote
end


            
            
            
            
            
            
