% Create three spheres using the sphere function:
[x y z] = sphere;
s1 = surf(x,y,z);
hold on
s2 = surf(x+3,y,z+3);
s3 = surf(x,y,z+6);
% Set the data aspect ratio using daspect:
daspect([1 1 1])
% Set the view:
view(30,10)
% Set the projection type using camproj:
camproj perspective
% Compose the scene around the current axes
camlookat(gca)
pause(2)
% Compose the scene around sphere s1
camlookat(s1)
pause(2)
% Compose the scene around sphere s2
camlookat(s2)
pause(2)
% Compose the scene around sphere s3
camlookat(s3)
pause(2)
camlookat(gca)

%%
surf(peaks)
axis vis3d off
for x = -200:5:200
    campos([x,5,10])
    drawnow
end

%%
surf(peaks); 
axis vis3d
xp = linspace(-150,40,50);
xt = linspace(25,50,50);
for i=1:50
     campos([xp(i),25,5]);
     camtarget([xt(i),30,0])
     drawnow
end

%%
sphere;
axis vis3d
hPan = pi; %sin(0:0.5:10*pi);
vPan = 0; cos(-2*pi:0.5:10*pi);
for k=1:300
   camorbit(pi/4,0)
   drawnow
   pause(.1)
end