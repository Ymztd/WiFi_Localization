function study_wall_spacing(out)
% Single side wall, centered ULAs, specular reflection from the image TX.
% Wall offset jointly sets excess delay, AoA, AoD and free-space spreading.
if nargin<1, out=pwd; end
c=299792458; fc=5.2e9; K=257; bw=80e6; f=(-128:128)*bw/K;
M=6; index=((0:M-1)'-(M-1)/2); steer=@(a) exp(2i*pi*.45*index*sind(a));
w=ones(M,1)/sqrt(M); pilot=sqrt(100/K);
noise=sqrt(10^((-174+10*log10(bw/K)+7)/10)/2);
opts=struct('paths',8,'rounds',3,'energy',99,'meters',1,'db',3,'prior',.65);
ys=linspace(-.12,.12,11); result=table;
for seed=[723 724 725]
    r=RandStream('mt19937ar','Seed',seed);
    Z=noise*(randn(r,M,M,K,numel(ys))+1i*randn(r,M,M,K,numel(ys)));
    for h=[.3 1 2 4 8]
        X=Z; Y=complex(zeros(M,K,numel(ys))); truth=zeros(K,numel(ys));
        for k=1:numel(ys)
            y=ys(k); d=hypot(16,y); bounce=hypot(16,2*h-y);
            aoa=asind(-y/d); refl=asind((2*h-y)/bounce);
            a=(steer(aoa)*steer(-aoa).').*reshape( ...
                pilot*c/(4*pi*fc*d)*exp(-2i*pi*(fc+f)*d/c),1,1,K);
            b=(steer(refl)*steer(refl).').*reshape( ...
                -.8*pilot*c/(4*pi*fc*bounce)*exp(-2i*pi*(fc+f)*bounce/c),1,1,K);
            truth(:,k)=reshape(sum(a(1,:,:).*reshape(w,1,M),2),[],1);
            X(:,:,:,k)=X(:,:,:,k)+a+b;
            Y(:,:,k)=reshape(sum(X(:,:,:,k).*reshape(w,1,M),2),M,K);
        end
        spring=inf_spring_plus_fit(Y,f,noise);
        for k=1:numel(ys)
            y=ys(k); d=hypot(16,y); bounce=hypot(16,2*h-y);
            target=[d/c*1e9,asind(-y/d)]; ref=[bounce/c*1e9,asind((2*h-y)/bounce)];
            for method=["OMP","SPRING+","M3","Radio SLAM"]
                if method=="OMP"
                    [parts,ts,angles]=inf_waveform_fit(Y(:,:,k),f,noise);
                    pick=double(~isempty(ts));
                else
                    if method=="SPRING+"
                        fit=spring(k);
                    else
                        mode='m3'; if method=="Radio SLAM", mode='radio'; end
                        fit=inf_paper_los_fit(X(:,:,:,k),f,w,noise,mode,opts);
                    end
                    parts=fit.parts; ts=fit.delays; angles=fit.angles; pick=fit.los;
                end
                estimate=[NaN NaN]; wave=zeros(K,1);
                if pick, estimate=[ts(pick)*1e9,angles(pick)]; wave=parts(:,pick); end
                m=los_quality_metrics(true,target,estimate,truth(:,k),wave);
                reflection=abs(ts*1e9-ref(1))<=1 & abs(angles-ref(2))<=3;
                if pick, reflection(pick)=false; end
                result=[result;table(seed,k,h,method,ref(1)-target(1),abs(ref(2)-target(2)), ...
                    numel(ts),pick,m.passed(1),m.passed(2),m.passed(3),m.errors(3), ...
                    m.passed(1)&&any(reflection),'VariableNames',{'Seed','Frame','Wall_m','Method', ...
                    'Delta_ns','Delta_deg','K','Selected','IDpass','WavePass','JointPass','NMSE_dB','BothMatched'})]; %#ok<AGROW>
            end
        end
    end
    writetable(result,fullfile(out,'wall_spacing.csv'));
    fprintf('Side wall seed %d complete\n',seed);
end
end
