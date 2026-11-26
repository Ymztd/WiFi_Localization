function frames = inf_spring_plus_fit(Y,frequency,noiseStd)
% SPRING+ CSI pipeline adapted to simulated per-frame calibrated pilot data.
[~,nFreq,nFrames] = size(Y);
df = frequency(2)-frequency(1);
bandwidth = nFreq*df;
angleGrid = -90:2:90;
nFFT = 4*2^nextpow2(nFreq);
delayGrid = (0:nFFT-1)/(nFFT*df);
frames = repmat(struct('parts',[],'delays',[],'angles',[],'los',0),1,nFrames);
for t = 1:nFrames
    sample = Y(:,:,t);
    count = delayOrder(sample,noiseStd);
    [frames(t).parts,frames(t).delays,frames(t).angles] = ...
        musicPaths(sample,frequency,angleGrid,delayGrid,count,noiseStd);
end
delayScale = max(3e-9,0.5/bandwidth);
for t = 1:nFrames
    frames(t).los = associate(frames,t,delayScale);
end
end

function count = delayOrder(sample,noiseStd)
% Estimate delay order with a truncated matrix pencil on the strongest row.
[~,rx] = max(sum(abs(sample).^2,2));
length = min(32,floor(size(sample,2)/2));
indices = (1:length)'+(0:size(sample,2)-length-1);
row = sample(rx,:);
[U,S,V] = svd(row(indices),'econ');
s = diag(S);
count = min(12,nnz(s > 2*noiseStd*(sqrt(size(indices,1))+sqrt(size(indices,2)))));
if count>0
    poles = eig((U(:,1:count)'*row(indices+1)*V(:,1:count))/S(1:count,1:count));
    count = nnz(abs(poles)>=0.85 & abs(poles)<=1.15);
end
end

function [parts,delays,angles] = musicPaths(Y,f,anglesGrid,delaysGrid,count,noiseStd)
[M,K] = size(Y);
parts = complex(zeros(K,0));
delays = [];
angles = [];
if count==0
    return
end
% Use the delay order to size the frequency smoothing aperture.
m = min(M,4);
k = min([64,K-1,max(24,5*count)]);
row = (1:m)';
offsets = reshape(row+(0:k-1)*M,[],1);
starts = reshape((0:M-m)'+(0:K-k)*M,1,[]);
X = Y(offsets+starts);
R = (X*X')/size(X,2);
[Es,eigenvalues] = eig(R,'vector');
[~,order] = sort(real(eigenvalues),'descend');
count = min([count,size(X,2),m*k-1]);
Es = Es(:,order(1:count));

% ||En'*a||^2 = ||a||^2 - ||Es'*a||^2. Use IFFT for all delays.
steering = exp(2i*pi*0.45*(0:m-1)'*sind(anglesGrid));
nFFT = numel(delaysGrid);
spectrum = zeros(numel(anglesGrid),nFFT);
for p = 1:count
    projected = steering'*reshape(Es(:,p),m,k);
    spectrum = spectrum + abs(ifft(projected,nFFT,2)*nFFT).^2;
end
spectrum = 1./max(1-spectrum/(m*k),1e-9);
% Find local maxima, including endpoints and the periodic delay boundary.
peak = spectrum>=circshift(spectrum,[0 1]) & spectrum>=circshift(spectrum,[0 -1]);
peak(2:end,:) = peak(2:end,:) & spectrum(2:end,:)>=spectrum(1:end-1,:);
peak(1:end-1,:) = peak(1:end-1,:) & spectrum(1:end-1,:)>=spectrum(2:end,:);
score = spectrum;
score(~peak) = -Inf;
atoms = complex(zeros(M*K,0));
nmsDelay = max(1,round(nFFT/(2*k)));
nmsAngle = max(2,round(numel(anglesGrid)/(6*m)));
for p = 1:count
    [value,idx] = max(score(:));
    if ~isfinite(value)
        break
    end
    [i,j] = ind2sub(size(score),idx);
    score(max(1,i-nmsAngle):min(end,i+nmsAngle),mod(j-1+(-nmsDelay:nmsDelay),nFFT)+1) = -Inf;
    a = exp(2i*pi*0.45*((0:M-1)'-(M-1)/2)*sind(anglesGrid(i))) ...
        *exp(-2i*pi*f*delaysGrid(j));
    if abs(a(:)'*Y(:))^2/numel(Y) <= 2*noiseStd^2*log(numel(score)/0.01)
        continue
    end
    next = [atoms,a(:)];
    if rcond(next'*next)<1e-9
        continue
    end
    atoms = next;
    delays(end+1) = delaysGrid(j); %#ok<AGROW>
    angles(end+1) = anglesGrid(i); %#ok<AGROW>
end
if ~isempty(delays)
    gain = atoms\Y(:);
    [delays,order] = sort(delays);
    angles = angles(order);
    parts = atoms(1:M:end,order).*gain(order).';
end
end

function chosen = associate(frames,t,delayScale)
% Causal moving window. Count distinct observations for density/support.
chosen = 0;
first = max(1,t-15);
if t-first<2 || isempty(frames(t).delays)
    return
end
points = zeros(0,4);
for j = first:t
    count = numel(frames(j).delays);
    points = [points; frames(j).delays(:),frames(j).angles(:), ...
        repmat(j,count,1),(1:count)']; %#ok<AGROW>
end
coord = points(:,1:2)./[delayScale 6];
neighbors = (coord(:,1)-coord(:,1).').^2+(coord(:,2)-coord(:,2).').^2<=1;
core = false(1,size(points,1));
for p = 1:numel(core)
    core(p) = numel(unique(points(neighbors(p,:),3)))>=3;
end
visited = false(size(core));
best = -Inf;
for seed = find(core)
    if visited(seed)
        continue
    end
    members = false(size(core));
    queue = seed;
    visited(seed) = true;
    while ~isempty(queue)
        at = queue(1);
        queue(1) = [];
        members = members | neighbors(at,:);
        next = find(neighbors(at,:) & core & ~visited);
        visited(next) = true;
        queue = [queue,next]; %#ok<AGROW>
    end
    here = find(members(:) & points(:,3)==t);
    if isempty(here)
        continue
    end
    center = median(coord(members,:),1);
    [~,nearest] = min(sum((coord(here,:)-center).^2,2));
    support = numel(unique(points(members,3)))/(t-first+1);
    if support<0.25
        continue
    end
    % SpotFi-style likelihood: support, limited spread and short delay.
    likelihood = 4*support - sum(var(coord(members,:),1,1)) - 0.12*center(1);
    if likelihood>best
        best = likelihood;
        chosen = points(here(nearest),4);
    end
end
end
