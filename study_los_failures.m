function study_los_failures(out,seeds)
% Matched-seed Wi-Fi-band factory experiments, with a physical direct ray.
root=fileparts(which('inf_localization_gui'));
if nargin<1, out=pwd; end
if nargin<2, seeds=[723 724 725]; end
config=fullfile(root,'config');
quad='D:/biye/code_f/env2024-main (1)/env2024-main/quadriga_src';
p=struct('bs',[0 0 8],'ueStart',[16 -2 1.5],'ueEnd',[16 2 1.5], ...
    'fcGHz',5.2,'bwMHz',80,'tones',257,'nTx',6,'nRx',6,'txDbm',20, ...
    'noiseFigure',7,'beam',[0 0],'duration',2,'frames',21, ...
    'aoaToleranceDeg',5,'scanMode','manual','useBox',false,'boxCenter',[8 0 4], ...
    'boxSize',[1 1.5 5],'boxLoss',20,'scenario','3GPP_38.901_InF_NLOS_SL');
opt=struct('paths',8,'rounds',3,'energy',99,'meters',1,'db',3,'prior',.65);
methods=["OMP","SPRING+","M3","Radio SLAM"];
cases=["upright","sweep","roll75","roll86","bw20"];
rows=table;
for seed=seeds
    p.seed=seed;
    for env=cases
        p.txElementRollDeg=0; p.bwMHz=80; p.beam=[0 0];
        switch env
            case "sweep", p.beam=[-45 45];
            case "roll75", p.txElementRollDeg=75;
            case "roll86", p.txElementRollDeg=86;
            case "bw20", p.bwMHz=20;
        end
        d=inf_channel_run(p,config,quad);
        assert(d.addedLos && all(~d.blocked) && all(sum(abs(d.losPilotFirstRx).^2,1)>0));
        if env=="upright"
            baselineNoise=d.Y-d.pilot*d.H; baseDelays=d.delayS;
        else
            assert(isequal(baseDelays,d.delayS));
            noise=d.Y-d.pilot*d.H;
            scale=sqrt(p.bwMHz/80);
            assert(norm(noise(:)-scale*baselineNoise(:))<1e-8*norm(noise(:)));
        end
        spring=inf_spring_plus_fit(d.Y,d.frequencyOffsetsHz,d.noisePerToneStd);
        if env=="upright"
            burst=spring;
            for first=1:2:p.frames
                ix=first:min(first+1,p.frames);
                burst(ix)=inf_spring_plus_fit(d.Y(:,:,ix),d.frequencyOffsetsHz,d.noisePerToneStd);
            end
        end
        for k=1:p.frames
            refT=d.referenceDelayS(k)*1e9; refA=d.anglesDeg(2,k);
            pw=d.pathDbm(1,k); gap=pw-max(d.pathDbm(2:end,k));
            for method=methods
                rescue=NaN; gapProbe=NaN; excess=NaN; passedGate=NaN; burstWinner=NaN;
                switch method
                    case "OMP"
                        [~,tau,aoa]=inf_waveform_fit(d.Y(:,:,k),d.frequencyOffsetsHz,d.noisePerToneStd);
                        chosen=double(~isempty(tau));
                    case "SPRING+"
                        fit=spring(k); tau=fit.delays; aoa=fit.angles; chosen=fit.los;
                        if env=="upright", burstWinner=burst(k).los; end
                    otherwise
                        X=d.mimoPilot(:,:,:,k); w=d.beamWeights(:,k); mode='m3';
                        if method=="Radio SLAM", mode='radio'; end
                        fit=inf_paper_los_fit(X,d.frequencyOffsetsHz,w,d.noisePerToneStd,mode,opt);
                        tau=fit.delays; aoa=fit.angles; chosen=fit.los;
                end
                match=abs(1e9*tau-refT)<=1 & abs(aoa-refA)<=3;
                success=chosen>0 && match(chosen);
                if method=="Radio SLAM" && any(match)
                    [~,best]=max(fit.power(match)); ids=find(match); id=ids(best);
                    gapProbe=max(fit.power)-fit.power(id);
                    excess=(tau(id)-min(tau))*299792458; passedGate=any(fit.eligible(match));
                    if ~success && ~passedGate && gapProbe>opt.db && excess<=opt.meters
                        trial=opt; trial.db=30;
                        other=inf_paper_los_fit(X,d.frequencyOffsetsHz,w,d.noisePerToneStd,mode,trial);
                        assert(isequal(tau,other.delays));
                        rescue=other.los>0 && match(other.los);
                    end
                elseif method=="M3" && ~success && (env=="upright" || env=="bw20")
                    trial=opt; trial.rounds=10;
                    other=inf_paper_los_fit(X,d.frequencyOffsetsHz,w,d.noisePerToneStd,mode,trial);
                    h=other.los;
                    rescue=h>0 && abs(other.delays(h)*1e9-refT)<=1 && abs(other.angles(h)-refA)<=3;
                end
                if chosen
                    estT=tau(chosen)*1e9; estA=aoa(chosen);
                else
                    estT=NaN; estA=NaN;
                end
                rows=[rows;table(env,seed,k,d.time(k),method,pw,gap,refT,refA,estT,estA,numel(tau),nnz(match), ...
                    chosen,success,gapProbe,excess,passedGate,rescue,burstWinner, ...
                    'VariableNames',{'Environment','Seed','Frame','Time_s','Method','LOS_dBm','LOS_minus_reflection_dB', ...
                    'True_ns','True_deg','Estimated_ns','Estimated_deg','CandidateCount','MatchCount','Chosen','Success', ...
                    'ProbeGap_dB','Excess_m','MatchPassedGate','ControlSuccess','TwoPacketChosen'})]; %#ok<AGROW>
            end
        end
        fprintf('%d %s complete\n',seed,env);
        writetable(rows,fullfile(out,'failure_frames.csv'));
    end
end
end
