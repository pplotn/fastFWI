%% Example of FWI for Marmousi II benchmark model.
%
% Press "Run" to launch the script
%
% Vladimir Kazei and Oleg Ovcharenko, 2019

tic
close all
clearvars
restoredefaultpath
spparms('bandden',0.0)

% Link core folders
addpath(genpath('../engine/'));
set(groot,'DefaultFigureColormap',rdbuMap())

% Create Fig/ folder where to store output images
figFolder = 'Fig/';
if exist(figFolder, 'dir')
    fprintf(['Exist ' figFolder '\n']);
else
    mkdir(figFolder);
    fprintf(['Create ' figFolder '\n']);
end

%% MODEL and GRID
% read Marmousi II model (Baseline)
dx = 50;
v.Base = dlmread('models/marm2/marm2_10.dat');
v.Base = imresize(v.Base, 10/dx, 'bilinear');

% append  N_ext_up points from above for the absorbing layer
N_ext_up = 5;
v.Base = [repmat(v.Base(1,:),5,1);  v.Base];

% grid creation
model.n  = size(v.Base);
model.h  = dx*[1 1];
z  = [-N_ext_up:model.n(1)-1-N_ext_up]*model.h(1);
x  = [0:model.n(2)-1]*model.h(2);
[zz,xx] = ndgrid(z,x);

model.x = x;
model.z = z;

% build linear initial model for FWI
v_Fun_Init = @(zz,xx)v.Base(1)+0.9e-3*max(zz-450,0);
v.Init = v_Fun_Init(zz,xx);

imagescc(v.Base,model,'Marmousi II',[figFolder,'true'])
imagescc(v.Init,model,'Marmousi II',[figFolder,'init'])

% model - converted to squared slowness
%baseline
m.Base = 1./v.Base(:).^2;
%initial
m.Init = 1./v.Init(:).^2;



%% DATA ACQUISITION
% set frequency range, not larger than min(1e3*v(:))/(7.5*dx) or smaller than 0.5
fMin  = 1; % this is the minimum frequency used for inversion
fFactor = 1.2; % factor to the next frequncy
fMax = 5; % this is the max frequency used for inversion

% receivers
model.xr = 5*dx:dx:16800;
model.zr = 5*dx*ones(1,length(model.xr));

% sources
model.xs = 5*dx:200:16800;
model.zs = 5*dx*ones(1,length(model.xs));

% for each frequency offsets are inverted sequentially each next is *Factor of perevious
minMaxOffset = 8000;
maxMaxOffset = 8000;

%v.Init = dlmread(['marm_' num2str(dx) '.dat']);
% dx replicates h(1)
model.dx = dx;



%% REGULARIZATION
% regFlag chooses the type of regularization to be applied
% -2 - Tikhonov;  -1 - MS; 1 - MGS;  2 - (TV); 3 - W_p^1;
% 0 - no regularization
flags.R = 3;
opts.R = loadRegPresets(flags.R);
% 1 - regularize update (usual for time-lapse),
% 0 - regularize model itself (blocky model)
opts.R.dmFlag = 0;

% this restricts the updates l and u are multiplied by this
opts.R.dvMask = zz>400;

% you can modify the parameters after presetting to improve regularization
% performance e.g. "opts.R.p = 1.5;"

%% LBFGSB PARAMETERS
% lbfgs "depth" - number of gradients
opts.m = 2;
% max number of iterations - number of search directions
opts.maxIts = 50;
%same including the number of line search steps
opts.maxTotalIts = 1000;
%output of functional through iterations
opts.printEvery = 1;
%stopping tolerance for the gradient
opts.pgtol = 10^(-9);
%relative decrease in misfit the larger the less precise
opts.factr = 1e11;

opts.histAll = 0;


%% MAIN LOOP OVER FREQUENCIES
it=0;
freq = fMin;
while freq<=fMax
    it=it+1;
    % acquire noisy data
    model.maxOffset = minMaxOffset;
    model.f = freq;
    
    DClean = F(m.Base,model);
    
    D0 = F(m.Init,model);
    
    % Gaussian noise
    mySNR = 100;
    
    noiseStandDev = 1/sqrt(mySNR);
    noiseStandDev = noiseStandDev * sqrt(mean(mean(abs(DClean).*abs(DClean))));
    D = DClean + sqrt(1/2)*(randn(size(DClean))*noiseStandDev+1i*randn(size(DClean))*noiseStandDev);
    
    snrDB = snr(DClean, D-DClean)
    matSNR  = db2pow(snrDB)
    
    % Mute offsets beyond the max limit
    while model.maxOffset <= maxMaxOffset
        for i=1:size(model.xr,2)
            for j=1:size(model.xs,2)
                if abs(model.xr(i)-model.xs(j))>model.maxOffset
                    D(i,j)=0;
                end
            end
        end
        
        %  FWI ================================================
        fwiResult = fwiFunc_Clean(i, m.Init, D, model, opts);
        % =====================================================
        
        figure;
        imagescc(fwiResult.final,model,[num2str(model.f) ' Hz'],[figFolder num2str(it)])
        
        % Relax regularization and increase affordable offset
        model.maxOffset = fFactor*model.maxOffset;
        opts.R.alphaTV = opts.R.alphaTV/fFactor;
        %opts.R.alpha = opts.R.alpha;
        %opts.histAll = optsArr(1).histAll;
        %m.InitArr(i) = 1./FWIArr(fix((sizeReg^2+1)/2)).final(:).^2;
        
        m.Init(:) = 1./fwiResult.final(:).^2;
        
    end
    m.Init = fwiResult.final(:).^-2;
    freq = freq*fFactor
end

%%
%%%%%%%%%%%%%%%%%
% FINAL PLOT
%%%%%%%%%%%%%%%%%
% fig = figure;
% fig.PaperUnits = 'inches';
% fig.PaperPosition = [0 0 24 8];
% vk = fwiResult.final;
% imagesc(x/1000,z/1000,vk,[min(v.Base(:)) max(v.Base(:))]); 
% xlabel('km'); ylabel('km'); title('Final'); c=colorbar; ylabel(c,'km/s');
% axis equal tight;
% print(fig, [figFolder,'/fwiFinal'], '-depsc');

figure;
imagescc(fwiResult.final,model,'Final',[figFolder 'final'])



toc;