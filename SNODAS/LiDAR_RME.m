[L,cmap,R,bbox] = geotiffread('snow-depth-final.tif');
I2=find(L<0);
L2=single(L);
L2(I2)=NaN;
Lx=bbox(1,1):bbox(2,1)-1;
Ly=bbox(1,2):bbox(2,2)-1;
Ly=flipud(Ly(:)); % reverse the order of the y vector
figure(2);clf
imagesc(Lx,Ly,L2);
Amap=ones(size(L2)); 
Amap(isnan(L2))=0;
alpha(Amap); hold on



%for n=1:length(S5)
%    plot(S5(n).X,S5(n).Y,'w-','LineWidth',3)
%end
