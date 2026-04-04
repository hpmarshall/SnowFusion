% SNODASmovieTest
latlim=[43.2 44.4]; lonlim=[-116.2 -114.6]; % set region of interest
Pstate='SWE'; % plot SWE
WYa=2014; % Water year to make a movie for  
MonthD={'10_Oct','11_Nov','12_Dec','01_Jan','02_Feb','03_Mar', ...
'04_Apr','05_May','06_Jun'};

% First lets set up the plot with Oct 1
hfig=figure('Renderer','opengl');
set(hfig,'position',[1 35 1280 671]) % make full screen (change for diff monitor)
WY=WYa(1);
R=load([num2str(WY-1) '/' MonthD{1} '/S' num2str(WY-1) '-10-1.mat']); % load Oct 1
Iy=find(R.lat>latlim(1) & R.lat<latlim(2));
Ix=find(R.lon>lonlim(1) & R.lon<lonlim(2));
lon=R.lon(Ix); lat=R.lat(Iy);
[LON,LAT]=meshgrid(lon,lat);
ISx=find(strncmp(Pstate,{r.name}',3)); % find the SWE data
St=R.r(ISx).data(Ix,Iy)';
St=full(St);
hG=plotSNODASvar9(LAT,LON,St,latlim,lonlim);
figure(hfig)
M(1)=getframe(hfig);
hT=suptitle([num2str(WY-1) '-10-1.mat']);
q=2;
for n4=1:length(MonthD) % loop over months
    if n4<4
        YY=num2str(WY-1);
    else
        YY=num2str(WY);
    end
    D=dir([YY '/' MonthD{n4} '/S*']); % get all the days
    jd=zeros(length(D),1);
    for n6=1:length(D)
        jd(n6)=datenum(D(n6).name(2:end-4),'yyyy-mm-dd');
    end
    [jd2,jx]=sort(jd);
    for n5=1:length(jx) % loop over days
        try
            R=load([YY '/' MonthD{n4} '/' D(jx(n5)).name]); % load current
            % now update all subplots
            St=R.r(Svars(n2,n3)).data(Ix,Iy)';
            Amap=ones(size(St)); Amap(St==0)=0; Amap(isnan(St))=0;
            set(hG,'cdata',St,'alphadata',Amap);
            set(hT,'String',D(jx(n5)).name(2:end));
            figure(hfig)
            %drawnow
            M(q)=getframe(hfig);
            q=q+1
        catch
            disp([YY '/' MonthD{n4} '/' D(jx(n5)).name ' did not load! skipping...'])
        end
    end
end
writerObj = VideoWriter('test2.avi');
writerObj.FrameRate=0.25;
open(writerObj);
writeVideo(writerObj,M)
close(writerObj)
