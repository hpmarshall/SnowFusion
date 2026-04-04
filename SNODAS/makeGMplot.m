load GMortho

%%
figure('Renderer','opengl','units','normalized','outerposition',[0 0 1 1])

%% usamap(latlim, lonlim)
usamap(latlim, lonlim)
framem off; mlabel off; plabel off; gridm off
geoshow(Z, R, 'DisplayType', 'surface', 'CData', A);
daspectm('m',3)
lighting phong
%view(3)
% plot BRB outline
hold on
myUTM=utmzone(mean(latlim),mean(lonlim)); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);
R100=R;
load POLSCATmap


%
[R2(1).lat,R2(1).lon]=minvtran(mstruct,Xall,Yall);
[R2(2).lat,R2(2).lon]=minvtran(mstruct,Rx,Ry);
[R2(3).lat,R2(3).lon]=minvtran(mstruct,H(:,1),H(:,2));
%[R2(4).lat,R2(4).lon]=minvtran(mstruct,H2(:,1),H2(:,2));
%[R2(5).lat,R2(5).lon]=minvtran(mstruct,H3(:,1),H3(:,2));
col='kgb';
%
dz=[0 50 40];
%
for n=1:3
    hold on
    R2(n).Z=ltln2val(Z,R100,R2(n).lat,R2(n).lon)+dz(n);
    h(n)=plot3m(double(R2(n).lat),double(R2(n).lon),double(R2(n).Z),[col(n) '.']);
end
set(h(1),'LineWidth',1,'Color',[0.7 0.7 0.7])
set(h(2),'LineWidth',4,'MarkerSize',8)
set(h(3),'LineWidth',4,'MarkerSize',8)
%
%
%view([-130 25])



% now plot SNOTELs
% r2=kml2struct('IdahoSNOTEL.kml')
% BB=[-117 -114 42 45];
% Lat=[r2(:).Lat];
% Lon=[r2(:).Lon];
% Ix=find(Lon>BB(1) & Lon<BB(2) & Lat>BB(3) & Lat<BB(4));
% r3=r2(Ix);
% for n=1:length(r3)
%     Sz=ltln2val(Z,R,r3(n).Lat,r3(n).Lon);
%     plot3m(r3(n).Lat,r3(n).Lon,Sz+50,'r+','LineWidth',2,'MarkerSize',6)
%     textm(r3(n).Lat,r3(n).Lon,Sz+500,r3(n).Name,'FontSize',10,'FontWeight','bold','Color','w')
% end
% %% add HW21 Lidar area
% plotKML('HW21.kml',Z,R)
% plotKML('DryCreekBoundary.kml',Z,R);
% plotKML('Stanley.kml',Z,R)
% plotKML('Bannock.kml',Z,R)
% plotKML('Sawtooth.kml',Z,R)
% plotKML('Bulltrout.kml',Z,R)

% plot all weather obs
[D,MWS]=xlsread('MESOWEST_CO.xls');
Ix=find(D(:,1)>latlim(1) & D(:,1)<latlim(2) & D(:,2)>lonlim(1) & D(:,2)<lonlim(2));
D=D(Ix,:);
MWS=MWS(Ix,:);
T=MWS(:,7);
S=MWS(:,2);
D(:,3)=ltln2val(Z,R100,D(:,1),D(:,2));
plot3m(D(:,1),D(:,2),D(:,3)+50,'y^','LineWidth',4,'MarkerSize',6)
t=strfind(T,'SNOTEL');
SIx=[];
for n=1:length(t)
    t2=t(n);
    t2=t2{:};
    if ~isempty(t2)
         plot3m(D(n,1),D(n,2),D(n,3)+50,'ro','LineWidth',3,'MarkerSize',8)
         %textm(D(n,1),D(n,2),Sz3,S{n},'Color','r','FontSize',10);
         T{n}
         S{n}
         SIx=[SIx;n];
    end
end

%axis([-74203 74203 4.6131e+06 4.7244e+06 913.94 3882.1])

%%
% set(gcf, 'PaperSize', [20 10])
% set(gcf, 'PaperPositionMode', 'manual');
% set(gcf, 'PaperUnits', 'inches');
% set(gcf, 'PaperPosition', [0 0 20 10]);
% %%
% print -dpng GM.png
% %print -dpdf -r300 GM.pdf
%northarrow('Latitude',latlim(1)+0.5,'longitude',lonlim(1)+0.5)
%axis([-66500 66500 4612000 4725600 1000 4000])
%print -dpng GrandMesaStudySite.png
%print -dpdf -r300 GrandMesaStudySite.pdf
        
%%

%