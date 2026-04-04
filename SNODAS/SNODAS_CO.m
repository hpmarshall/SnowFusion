% plot SNODAS results from Colorado
load TEMP/SNODAS_CO200607
%% fix the dataset
t=squeeze([Snodas(1).Precip(1,1,:)]);
I2=find(isfinite(t));
for n=1:length(S2)
    Snodas(1).(S2{n})=Snodas(1).(S2{n})(:,:,1:max(I2));
end
Snodas(1).date={Fnames{1:max(I2)}};
%%
t=squeeze([Snodas(2).Precip(1,1,366:end)]);
I3=find(isfinite(t));
for n=1:length(S2)
    Snodas(2).(S2{n})=Snodas(2).(S2{n})(:,:,366:(max(I3)+365));
end
Snodas(2).date={Fnames{366:end}};
Snodas(1).lat=lat(Iy); Snodas(1).lon=lon(Ix);
Snodas(2).lat=lat(Iy); Snodas(2).lon=lon(Ix);
save SNODAS_CO200607 Snodas
