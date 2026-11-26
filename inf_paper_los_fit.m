function fit = inf_paper_los_fit(X,f,w,noiseStd,method,opt)
% Inputs are noisy, calibrated per-port pilots, antenna weights and settings.
% X is Rx x Tx x frequency. Both arrays use 0.45 wavelength spacing.
X = double(X);
[nr,nt,K] = size(X);
fit = struct('parts',complex(zeros(K,0)),'delays',[],'angles',[],'departure',[], ...
    'los',0,'power',[],'eligible',false(1,0),'cost',[],'nullCost',NaN,'reason',"");
if nr<2 || nt<2
    fit.reason = "AoA/AoD requires TX and RX each to have at least 2 element";
    return
end
if strcmp(method,'m3')
    par = subspaceSeeds(X,f,noiseStd,opt.paths);
    par = sage(X,f,par,opt.rounds);
    beamPower = [];
else
    [par,beamPower] = beamPeaks(X,f,noiseStd,opt.energy);
end
if isempty(par)
    fit.reason = "No detected multipath candidates";
    return
end
[~,ix] = sort(par(:,1)); par = par(ix,:);
atoms = complex(zeros(numel(X),size(par,1)));
for i=1:size(par,1)
    a = atom(nr,nt,f,par(i,:));
    atoms(:,i) = a(:);
end
% SVD-based minimum norm also handles coincident templates.
gain = lsqminnorm(atoms,X(:));
fit.delays = par(:,1).'*1e-9; fit.angles = par(:,2).'; fit.departure = par(:,3).';
for i=1:numel(gain)
    a = reshape(atoms(:,i),nr,nt,K);
    fit.parts(:,i) = gain(i)*reshape(sum(a(1,:,:).*reshape(w,1,nt,1),2),K,1);
end
if strcmp(method,'m3')
    fit.power = 10*log10(max(realmin,K*abs(gain.').^2));
    fit.eligible = true(size(fit.delays)); fit.cost = nan(size(fit.delays));
    fit.los = 1;
    fit.reason = "Assumes LOS exists · Earliest SAGE Candidate (GUI rule)";
else
    fit.power = 10*log10(max(realmin,beamPower(ix)));
    [fit.los,fit.eligible,fit.cost,fit.nullCost] = geometryChoice(par,fit.power,opt);
    if fit.los>0
        fit.reason = sprintf('Passed both gates %d paths · LOS cost %.2f / No LOS %.2f', ...
            nnz(fit.eligible),fit.cost(fit.los),fit.nullCost);
    elseif any(fit.eligible)
        fit.reason = sprintf('Geometry selects no LOS · No LOS cost %.2f',fit.nullCost);
    else
        fit.reason = "No candidate passes both distance and power gates";
    end
end
end

function a = array(n,angle)
a = exp(2i*pi*.45*((0:n-1)'-(n-1)/2)*sind(angle));
end

function a = atom(nr,nt,f,p)
a = (array(nr,p(2))*array(nt,p(3)).').*reshape(exp(-2i*pi*f*(p(1)*1e-9)),1,1,[]);
end

function par = subspaceSeeds(X,f,noise,maxPaths)
% M3 Sec. 3.2.2: smooth over Rx, Tx and tones, then search a 3D MUSIC grid.
[nr,nt,K] = size(X); r=min(3,nr); t=min(3,nt); h=min(12,floor(K/2));
[i,j,k]=ndgrid(0:r-1,0:t-1,0:h-1); offsets=i(:)+nr*j(:)+nr*nt*k(:);
[i,j,k]=ndgrid(0:nr-r,0:nt-t,0:K-h);
starts=1+i(:)+nr*j(:)+nr*nt*k(:);
starts=starts(round(linspace(1,numel(starts),min(512,numel(starts)))));
S=X(offsets+starts(:).'); R=S*S'/numel(starts);
[U,e]=eig(R,'vector'); [e,idx]=sort(real(e),'descend');
order=min([maxPaths,numel(e)-1,nnz(e>2*noise^2*(1+sqrt(size(S,1)/size(S,2)))^2*1.3)]);
par=zeros(0,3);
if order==0, return, end
angles=-90:10:90; G=kron(array(t,angles),array(r,angles));
nfft=2*2^nextpow2(K); dt=1e9/(nfft*(f(2)-f(1)));
power=zeros(size(G,2),nfft);
for q=1:order
    spatial=G'*reshape(U(:,idx(q)),r*t,h);
    power=power+abs(ifft(spatial,nfft,2)*nfft).^2;
end
% Fixed norm steering vectors make maximizing signal-subspace energy
% equivalent to minimizing the squared noise-subspace projection.
L=numel(angles); power=reshape(power,L,L,nfft);
peak=power>=circshift(power,1,3) & power>=circshift(power,-1,3);
for dim=1:2
    left=repmat({':'},1,3); right=left;
    left{dim}=1:L-1; right{dim}=2:L;
    peak(left{:})=peak(left{:}) & power(left{:})>=power(right{:});
    peak(right{:})=peak(right{:}) & power(right{:})>=power(left{:});
end
score=power; score(~peak)=-Inf;
for q=1:order
    [v,id]=max(score(:)); if ~isfinite(v), break, end
    [u,b,d]=ind2sub(size(score),id);
    candidate=[(d-1)*dt,angles(u),angles(b)];
    a=atom(nr,nt,f,candidate);
    if abs(a(:)'*X(:))^2/numel(X)>2*noise^2*log(numel(score)/.01)
        par(end+1,:)=candidate; %#ok<AGROW>
    end
    score(max(1,u-1):min(L,u+1),max(1,b-1):min(L,b+1), ...
        mod(d-1+(-2:2),nfft)+1)=-Inf;
end
end

function par = sage(X,f,par,rounds)
% Frequency-domain path-wise interference cancellation, M3 Eqs. (2)-(8).
[nr,nt,K]=size(X); count=size(par,1);
if count==0, return, end
A=complex(zeros(numel(X),count));
for p=1:count
    a=atom(nr,nt,f,par(p,:)); A(:,p)=a(:);
end
gain=lsqminnorm(A,X(:)); residual=X(:)-A*gain;
period=1e9/(f(2)-f(1)); width=period/K;
for sweep=1:rounds
    initial=norm(residual);
    for p=1:count
        isolated=reshape(residual+A(:,p)*gain(p),nr,nt,K);
        v=par(p,:); rx=array(nr,v(2)); tx=array(nt,v(3));
        s=reshape(rx'*reshape(isolated,nr,[]),nt,K).'*conj(tx);
        v(1)=mod(refine(v(1),v(1)-width,v(1)+width, ...
            @(x) abs(exp(2i*pi*f*x*1e-9)*s)),period);
        spatial=reshape(reshape(isolated,nr*nt,K)*exp(2i*pi*f.'*v(1)*1e-9),nr,nt);
        y=spatial*conj(tx);
        v(2)=refine(v(2),max(-90,v(2)-15),min(90,v(2)+15),@(x) abs(array(nr,x)'*y));
        y=spatial.'*conj(array(nr,v(2)));
        v(3)=refine(v(3),max(-90,v(3)-15),min(90,v(3)+15),@(x) abs(array(nt,x)'*y));
        a=atom(nr,nt,f,v); A(:,p)=a(:); par(p,:)=v;
        gain(p)=a(:)'*isolated(:)/numel(X); residual=isolated(:)-a(:)*gain(p);
    end
    if initial-norm(residual)<=1e-5*max(initial,realmin), break, end
end
end

function value=refine(old,lo,hi,score)
value=fminbnd(@(x) -score(x),lo,hi,optimset('TolX',1e-3,'Display','off'));
if score(old)>=score(value), value=old; end
end

function [par,powers]=beamPeaks(X,f,noise,energy)
% Radio-SLAM-inspired SVD on a synthetic Tx/Rx beam power map.
% This CSI-based GUI adaptation omits the paper's full joint SLAM solver.
[nr,nt,K]=size(X); grid=-90:4:90; grid=unique([grid 90]);
R=array(nr,grid)/sqrt(nr); T=array(nt,grid)/sqrt(nt);
beam=pagemtimes(pagemtimes(R',X),conj(T));
B=sum(abs(beam).^2,3); [U,S,V]=svd(B,'econ'); s=diag(S);
par=zeros(0,3); powers=[];
if sum(s.^2)==0, return, end
rank=find(cumsum(s.^2)>=energy/100*sum(s.^2)*(1-1e-12),1);
floorP=2*noise^2*(K+4*sqrt(K));
points=zeros(0,3);
for k=1:rank
    increment=U(:,k)*V(:,k).'; [~,idx]=max(increment(:)); [i,j]=ind2sub(size(B),idx);
    if B(i,j)>floorP, points(end+1,:)=[grid(i),grid(j),B(i,j)]; end %#ok<AGROW>
end
[~,order]=sort(points(:,3),'descend'); points=points(order,:);
N=4*2^nextpow2(K);
while ~isempty(points)
    near=abs(points(:,1)-points(1,1))<=max(4,45/nr) & abs(points(:,2)-points(1,2))<=max(4,45/nt);
    center=sum(points(near,1:2).*points(near,3),1)/sum(points(near,3));
    points(near,:)=[];
    [~,i]=min(abs(grid-center(1))); [~,j]=min(abs(grid-center(2)));
    ii=max(1,i-1):min(numel(grid),i+1); jj=max(1,j-1):min(numel(grid),j+1);
    if numel(ii)==3 && numel(jj)==3
        [x,y]=ndgrid(grid(ii)-grid(i),grid(jj)-grid(j)); x=x(:); y=y(:);
        z=B(ii,jj); coef=[ones(9,1),x,y,x.^2,x.*y,y.^2]\z(:);
        hess=[2*coef(4) coef(5);coef(5) 2*coef(6)];
        if all(eig(hess)<0) && rcond(hess)>1e-8
            vertex=-(hess\coef(2:3)).';
            if all(abs(vertex)<=4), center=[grid(i),grid(j)]+vertex; end
        end
    end
    [~,i]=min(abs(grid-center(1))); [~,j]=min(abs(grid-center(2)));
    cir=abs(ifft(reshape(beam(i,j,:),1,K),N)).^2; [~,d]=max(cir);
    par(end+1,:)=[(d-1)*1e9/(N*(f(2)-f(1))),center]; %#ok<AGROW>
    powers(end+1)=B(i,j); %#ok<AGROW>
end
end

function [selected,eligible,cost,nullCost]=geometryChoice(par,powers,opt)
% Synchronized, known-heading 2D adaptation of the paper's competing
% hypotheses. Profile out each single-bounce landmark along its range segment.
d=par(:,1)*.299792458;
eligible=(d-min(d)<=opt.meters).' & (max(powers)-powers<=opt.db);
cost=nan(1,numel(d)); selected=0;
% TX looks along +x and RX angles use the opposite broadside hemisphere.
start=d.*[cosd(par(:,2)),-sind(par(:,2))];
finish=d.*[cosd(par(:,3)),sind(par(:,3))];
scale=max(.3,d*sind(4)); % range floor and approximate angular spread, metres
nullCost=geometryCost(start,finish,scale,0)-2*log(1-opt.prior);
for k=find(eligible)
    cost(k)=geometryCost(start,finish,scale,k)-2*log(opt.prior/nnz(eligible));
end
[best,id]=min(cost,[],'omitnan');
if ~isempty(best) && best<nullCost, selected=id; end
end

function best=geometryCost(a,b,scale,los)
v=b-a; den=max(sum(v.^2,2),eps);
seeds=[median((a+b)/2,1);(a+b)/2];
best=Inf;
for j=1:size(seeds,1)
    x=seeds(j,:);
    for iter=1:40
        t=max(0,min(1,sum((x-a).*v,2)./den));
        target=a+t.*v; angular=zeros(size(den));
        if los>0
            target(los,:)=(a(los,:)+b(los,:))/2;
            angular(los)=sum(v(los,:).^2)/4;
        end
        q=(sum((x-target).^2,2)+angular)./scale.^2;
        best=min(best,sum(log1p(q)));
        w=1./((1+q).*scale.^2);
        next=sum(w.*target,1)/sum(w);
        if norm(x-next)<1e-4, break, end
        x=next;
    end
end
end
