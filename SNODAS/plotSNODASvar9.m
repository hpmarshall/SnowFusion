function G=plotSNODASvar9(LAT,LON,S,latlim,lonlim)
h=usamap(latlim, lonlim);
set(h,'nextplot','replacechildren');
Amap=ones(size(S)); Amap(S==0)=0; Amap(isnan(S))=0;
G=geoshow(LAT,LON,S,'displaytype','texturemap'); 
caxis([0 1000])
colorbar('location','north')
set(G,'facecolor','texturemap','cdata',S);
set(G,'edgecolor','none','facealpha','texture','alphadata',Amap);
set(G,'backfacelighting','unlit');
setm(h,'FontSize',16,'FontWeight','bold')

%%
hold on
[S,A2]=shaperead('BRB_outline.shp');
myUTM=utmzone(mean(latlim),mean(lonlim)); % use range of lat/lon to get zone
mstruct = defaultm('utm');
mstruct.zone = myUTM;
mstruct = defaultm(mstruct);
[S.lat,S.lon] = minvtran(mstruct,S.X,S.Y);
hp9=plot3m(S.lat,S.lon,100*ones(size(S.lat)),'w','linewidth',4)
set(hp9,'Color',[0.4 0.4 0.4])

%% add HW21 Lidar area
[latk,lonk]=plotKML3('HW21.kml')
textm(latk,lonk,200,'HW21','FontSize',16,'FontWeight','bold','Color',[0.4 0.4 0.4])
[latk,lonk]=plotKML3('DryCreekBoundary.kml');
textm(latk,lonk,200,'DCEW','FontSize',16,'FontWeight','bold','Color',[0.4 0.4 0.4])

%% now plot SNOTELs
r2=kml2struct('IdahoSNOTEL.kml')
BB=[lonlim latlim];
Lat=[r2(:).Lat];
Lon=[r2(:).Lon];
Ix=find(Lon>BB(1) & Lon<BB(2) & Lat>BB(3) & Lat<BB(4));
r3=r2(Ix);
for n=1:length(r3)
    plotm(r3(n).Lat,r3(n).Lon,'k+','LineWidth',3,'MarkerSize',8)
    textm(r3(n).Lat+0.01,r3(n).Lon+0.01,200,r3(n).Name(1),'FontSize',18,'FontWeight','bold','Color',[0.4 0.4 0.4])
end

function [latk,lonk]=plotKML3(filename)
% reads KML file and plots on map in 3D
filename
r5=kml_shapefile(filename);
Xall=[];Yall=[];
for n=1:length(r5)
    hp9=plot3m(r5(n).Y,r5(n).X,100*ones(size(r5(n).Y)),'w','LineWidth',3);
    set(hp9,'Color',[0.4 0.4 0.4])
    Xall=[Xall;r5(n).X(:)];
    Yall=[Yall;r5(n).Y(:)];
end
latk=nanmean(Yall);
lonk=nanmean(Xall);

function kmlStruct = kml2struct(kmlFile)
% kmlStruct = kml2struct(kmlFile)
%
% Import a .kml file as a vector array of shapefile structs, with Geometry, Name,
% Description, Lon, Lat, and BoundaryBox fields.  Structs may contain a mix
% of points, lines, and polygons.
%
% .kml files with folder structure will not be presented as such, but will
% appear as a single vector array of structs.
%
% 

[FID msg] = fopen(kmlFile,'rt');

if FID<0
    error(msg)
end

txt = fread(FID,'uint8=>char')';
fclose(FID);

expr = '<Placemark.+?>.+?</Placemark>';

objectStrings = regexp(txt,expr,'match');

Nos = length(objectStrings);

for ii = 1:Nos
    ii
    % Find Object Name Field
    bucket = regexp(objectStrings{ii},'<name.*?>.+?</name>','match');
    if isempty(bucket)
        name = 'undefined';
    else
        % Clip off flags
        name = regexprep(bucket{1},'<name.*?>\s*','');
        name = regexprep(name,'\s*</name>','');
    end
    
    % Find Object Description Field
    bucket = regexp(objectStrings{ii},'<description.*?>.+?</description>','match');
    if isempty(bucket)
        desc = '';
    else
        % Clip off flags
        desc = regexprep(bucket{1},'<description.*?>\s*','');
        desc = regexprep(desc,'\s*</description>','');
    end
    
    geom = 0;
    % Identify Object Type
    if ~isempty(regexp(objectStrings{ii},'<Point', 'once'))
        geom = 1;
    elseif ~isempty(regexp(objectStrings{ii},'<LineString', 'once'))
        geom = 2;
    elseif ~isempty(regexp(objectStrings{ii},'<Polygon', 'once'))
        geom = 3;
    end
    
    switch geom
        case 1
            geometry = 'Point';
        case 2
            geometry = 'Line';
        case 3
            geometry = 'Polygon';
        otherwise
            geometry = '';
    end
    
    % Find Coordinate Field
    bucket = regexp(objectStrings{ii},'<coordinates.*?>.+?</coordinates>','match');
    % Clip off flags
    coordStr = regexprep(bucket{1},'<coordinates.*?>(\s+)*','');
    coordStr = regexprep(coordStr,'(\s+)*</coordinates>','');
    % Split coordinate string by commas or white spaces, and convert string
    % to doubles
    coordMat = str2double(regexp(coordStr,'[,\s]+','split'));
    % Rearrange coordinates to form an x-by-3 matrix
    [m,n] = size(coordMat);
    coordMat = reshape(coordMat,3,m*n/3)';
    
    % define polygon in clockwise direction, and terminate
    [Lat, Lon] = poly2ccw(coordMat(:,2),coordMat(:,1));
    if geom==3
        Lon = [Lon;NaN];
        Lat = [Lat;NaN];
    end
    
    % Create structure
    kmlStruct(ii).Geometry = geometry;
    kmlStruct(ii).Name = name;
    kmlStruct(ii).Description = desc;
    kmlStruct(ii).Lon = Lon;
    kmlStruct(ii).Lat = Lat;
    kmlStruct(ii).BoundingBox = [[min(Lon) min(Lat);max(Lon) max(Lat)]];
end
