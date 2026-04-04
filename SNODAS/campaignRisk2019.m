latlim=[38.8 39.2]; lonlim=[-108.4 -107.6]; % set region of interest
Pstate='Snow temp'; % get Snow melt
Pstate2='SWE'; % get SWE
% lets start with March 1-12
YR=2004:2018; % 15 yrs of data
MarSWE2=zeros(48,96,15);
MarTemp2=zeros(48,96,15);
for q=1:length(YR)
    q
    n=1;
    R=load([num2str(YR(q)) '/03_Mar/S' num2str(YR(q)) '-3-' num2str(n) '.mat']); % load Mar date
    Iy=find(R.lat>latlim(1) & R.lat<latlim(2));
    Ix=find(R.lon>lonlim(1) & R.lon<lonlim(2));
    lon=R.lon(Ix); lat=R.lat(Iy);
    MarSWE=zeros(length(lat),length(lon),12);
    MarMelt=zeros(length(lat),length(lon),12);
    for n=1:12
        R=load([num2str(YR(q)) '/03_Mar/S' num2str(YR(q)) '-3-' num2str(n) '.mat']); % load Mar date
        ISx=find(strncmp(Pstate,{R.r.name}',length(Pstate))); % find the SWE data
        St=R.r(ISx).data(Ix,Iy)';
        MarMelt(:,:,n)=full(St)/10;
        ISx=find(strncmp(Pstate2,{R.r.name}',length(Pstate2))); % find the SWE data
        St=R.r(ISx).data(Ix,Iy)';
        MarSWE(:,:,n)=full(St)/10;
    end
    MarSWE2(:,:,q)=median(MarSWE,3); % get median SWE for each pixel
    MarTemp2(:,:,q)=max(MarMelt,[],3); % sum all the melt during this period
end
save('MarGM_15yrs.mat','MarSWE2','MarTemp2','YR','lon','lat')

