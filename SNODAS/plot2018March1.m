% SNODAS plot
latlim=[38.8 39.2]; lonlim=[-108.4 -107.6]; % set region of interest
Pstate='Snow melt'; % plot SWE
WYa=2014; % Water year to make a movie for  
MonthD={'10_Oct','11_Nov','12_Dec','01_Jan','02_Feb','03_Mar', ...
'04_Apr','05_May','06_Jun'};

% First lets set up the plot with Oct 1
hfig=figure('Renderer','opengl');
set(hfig,'position',[1 35 1280 671]) % make full screen (change for diff monitor)
WY=WYa(1);
R=load([num2str(2018) '/' MonthD{6} '/S' num2str(2018) '-3-1.mat']); % load Mar 1
Iy=find(R.lat>latlim(1) & R.lat<latlim(2));
Ix=find(R.lon>lonlim(1) & R.lon<lonlim(2));
lon=R.lon(Ix); lat=R.lat(Iy);
[LON,LAT]=meshgrid(lon,lat);
ISx=find(strncmp(Pstate,{R.r.name}',length(Pstate))); % find the SWE data
St=R.r(ISx).data(Ix,Iy)';
St=full(St);
zlim=[min(St(:)) max(St(:))];
hG=plotSNODASvar9_v2(LAT,LON,St,latlim,lonlim,zlim);