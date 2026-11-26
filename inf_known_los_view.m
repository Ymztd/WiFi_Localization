function fig=inf_known_los_view(data,initialFrame)
% Paired OMP ablations using exact array components from the InF generator.
if nargin<2, initialFrame=1; end
fig=uifigure('Name','Known LOS parameter-estimation controls','Position',[65 50 1540 950]);
root=uigridlayout(fig,[5 3]);
root.RowHeight={42,30,'1x','1x',80};
controls=uigridlayout(root,[1 8]); controls.Layout.Column=[1 3];
controls.ColumnWidth={150,75,75,80,120,150,100,'1x'};
experiment=uidropdown(controls,'Items',{'Weak LOS','Nearby-reflection ablation','Reflection coherent phase','Clock and array calibration'}, ...
    'ValueChangedFcn',@changed,'Tag','KnownLosExperiment');
uilabel(controls,'Text','Current frame');
frame=uieditfield(controls,'numeric','Value',initialFrame,'Limits',[1 numel(data.time)], ...
    'RoundFractionalValues','on','ValueChangedFcn',@changed);
uibutton(controls,'Text','Run controls','ButtonPushedFcn',@changed,'Tag','RunKnownLos');
uilabel(controls,'Text','Calibration term');
calibration=uidropdown(controls,'Items',{'Common delay ns','Array phase slope °'},'ValueChangedFcn',@changed);
uibutton(controls,'Text','Export trials','ButtonPushedFcn',@exportResults);
uilabel(controls,'Text','A original selection B truth-assisted association C Only LOS single-path fit');
info=uilabel(root,'WordWrap','on'); info.Layout.Row=2; info.Layout.Column=[1 3];
ax=gobjects(1,6);
for axisIndex=1:6
    panel=uipanel(root,'BorderType','none');
    panel.Layout.Row=3+floor((axisIndex-1)/3);
    panel.Layout.Column=1+mod(axisIndex-1,3);
    cellLayout=uigridlayout(panel,[1 1],'Padding',[0 0 0 0]);
    ax(axisIndex)=uiaxes(cellLayout);
end
status=uitextarea(root,'Editable','off'); status.Layout.Row=5; status.Layout.Column=[1 3];
tableResult=table; samples=struct([]);
changed();
    function changed(~,~)
        try
            compute();
        catch err
            status.Value={err.message};
            rethrow(err)
        end
    end
    function compute()
        k=round(frame.Value); f=data.frequencyOffsetsHz;
        L=double(data.losArrayPilot(:,:,k)); R=double(data.competitorArrayPilot(:,:,k));
        noise=data.Y(:,:,k)-data.pilot*data.H(:,:,k);
        rest=data.Y(:,:,k)-L-R-noise;
        trueT=data.referenceDelayS(k)*1e9; trueA=data.anglesDeg(2,k);
        slot=data.competitorSlot(k);
        if ~data.isLos || norm(L(:))==0
            error('No physical path available in this frame: LOS.');
        end
        switch experiment.Value
            case 'Weak LOS', levels=[0 5 10 15 20 30]; label='LOS extra attenuation (dB)';
            case 'Nearby-reflection ablation', levels=[1 .75 .5 .25 0]; label='Competing-reflection retained amplitude';
            case 'Reflection coherent phase', levels=0:45:315; label='Competing-reflection extra phase (°)';
            otherwise
                if strcmp(calibration.Value,'Common delay ns')
                    levels=[0 1 2 5 10]; label='Common delay bias (ns)';
                else
                    levels=[0 .5 1 2 5 10]; label='Spatial-frequency equivalent angle bias (°)';
                end
        end
        rows=struct([]); samples=repmat(struct('mixture',[],'pure',[],'direct',[]),1,numel(levels));
        for j=1:numel(levels)
            value=levels(j); direct=L; reflection=R; shift=ones(size(L));
            if strcmp(experiment.Value,'Weak LOS'), direct=L*10^(-value/20); end
            if strcmp(experiment.Value,'Nearby-reflection ablation'), reflection=value*R; end
            if strcmp(experiment.Value,'Reflection coherent phase'), reflection=R*exp(1i*pi*value/180); end
            if strcmp(experiment.Value,'Clock and array calibration')
                if strcmp(calibration.Value,'Common delay ns')
                    shift=repmat(exp(-2i*pi*f*value*1e-9),size(L,1),1);
                else
                    m=((0:size(L,1)-1)'-(size(L,1)-1)/2);
                    shift=repmat(exp(2i*pi*.45*m*sind(value)),1,numel(f));
                end
            end
            mixture=(direct+reflection+rest+noise).*shift;
            pure=(direct+noise).*shift;
            [parts,t,a]=inf_waveform_fit(mixture,f,data.noisePerToneStd);
            [~,aReference,~,reference]=singlePath(direct.*shift,f);
            candidate=nan; ambiguity=false;
            if ~isempty(t)
                steering=exp(2i*pi*.45*((0:size(L,1)-1)'-(size(L,1)-1)/2)*sind(a));
                template=reshape(steering,size(L,1),1,[]).* ...
                    reshape(exp(-2i*pi*f(:)*t(:).'),1,numel(f),[]);
                normalized=reshape(template,[],numel(t));
                scores=abs(normalized'*reference(:))./vecnorm(normalized).';
                scores=scores/max(norm(reference(:)),realmin);
                [sorted,order]=sort(scores,'descend'); candidate=order(1);
                % A proxy reference, not a geometric error pass window.
                ambiguity=numel(sorted)>1 && sorted(1)-sorted(2)<.02;
            end
            for mode=1:3
                if mode<3
                    pick=1; if mode==2, pick=candidate; end
                    estimateT=NaN; estimateA=NaN; wave=zeros(numel(f),1);
                    if ~isempty(t) && isfinite(pick)
                        estimateT=t(pick)*1e9; estimateA=a(pick); wave=parts(:,pick);
                    end
                else
                    [estimateT,estimateA,wave]=singlePath(pure,f);
                end
                nmse=10*log10(max(norm(wave-direct(1,:).')^2,realmin)/max(norm(direct(1,:))^2,realmin));
                row=struct('Frame',k,'Time_s',data.time(k),'Experiment',string(experiment.Value), ...
                    'Level',value,'Mode',mode,'DelayError_ns',estimateT-trueT, ...
                    'AngleError_deg',estimateA-trueA,'RangeError_m',.299792458*(estimateT-trueT), ...
                    'NMSE_dB',nmse,'CandidateCount',numel(t),'AssociationAmbiguous',mode==2 && ambiguity, ...
                    'LOSModelMismatch_deg',aReference-trueA,'CompetitorSlot',slot);
                rows=[rows;row]; %#ok<AGROW>
            end
            samples(j)=struct('mixture',mixture,'pure',pure,'direct',direct);
        end
        tableResult=struct2table(rows);
        fig.UserData=tableResult;
        names={'A original selection','B truth-assisted association','C Only LOS'};
        metrics={'DelayError_ns','AngleError_deg','NMSE_dB'};
        titles={'Delay error (ns), multiply by 0.2998 for range error m','AoA error (°)','LOS Waveform NMSE (dB)'};
        for j=1:3
            cla(ax(j)); hold(ax(j),'on');
            for mode=1:3
                subset=tableResult(tableResult.Mode==mode,:);
                plot(ax(j),subset.Level,subset.(metrics{j}),'o-','DisplayName',names{mode});
            end
            xlabel(ax(j),label); title(ax(j),titles{j}); pos_plot_style(ax(j)); legend(ax(j),'Location','best');
        end
        delay=linspace(trueT-12,trueT+12,65);
        angle=linspace(max(-89,trueA-10),min(89,trueA+10),51);
        % Compare last controlled level. Single-component profile likelihood.
        showCost(ax(4),samples(end).mixture,f,delay,angle,trueT,trueA,'Mixture single-component fit cost');
        showCost(ax(5),samples(end).pure,f,delay,angle,trueT,trueA,'Only LOS single-component fit cost');
        cla(ax(6)); hold(ax(6),'on');
        for j=1:numel(levels)
            subset=tableResult(tableResult.Level==levels(j),:);
            scatter(ax(6),levels(j),subset.CandidateCount(1),35,'filled');
            if subset.AssociationAmbiguous(2)
                plot(ax(6),levels(j),subset.CandidateCount(1),'rx','MarkerSize',13);
            end
        end
        xlabel(ax(6),label); title(ax(6),'Candidate count red crosses indicate ambiguous assisted associations'); pos_plot_style(ax(6));
        ratio=10*log10(norm(L(:))^2/max(norm(R(:))^2,realmin));
        snr=10*log10(norm(L(:))^2/max(norm(noise(:))^2,realmin));
        info.Text=sprintf('%s | t %.2f s | competing cluster #%d | LOS/ competing cluster %.1f dB | LOS realized SNR %.1f dB | coherence %.3f', ...
            char(data.scenario),data.time(k),slot,ratio,snr,data.competitorCoherence(k));
        status.Value={...
            'B using pure LOS reference-template correlation association, without ±1 ns / ±3° error-window frame filtering. Red crosses: top-two score gap below 0.02.', ...
            'B is a truth-assisted proxy association, does not guarantee a unique physical path identity. C uses continuous single-path refinement, and A/B of OMP estimators differ.', ...
            sprintf('Bottom-row cost maps use the last level %.2f, Single-component cost includes other multipath contributions, cannot be interpreted as full multipath Fisher information.',levels(end))};
    end
    function exportResults(~,~)
        [file,path]=uiputfile('*.csv','Export known LOS control results');
        if ~isequal(file,0), writetable(tableResult,fullfile(path,file)); end
    end
end

function [delay,angle,wave,reference]=singlePath(Y,f)
M=size(Y,1); K=numel(f); N=4*2^nextpow2(K);
indices=((0:M-1)'-(M-1)/2);
angles=-90:2:90;
steering=exp(2i*pi*.45*indices*sind(angles));
padded=complex(zeros(M,N)); padded(:,mod(-floor(K/2):ceil(K/2)-1,N)+1)=Y;
power=abs(steering'*ifft(padded,[],2)).^2;
[~,peak]=max(power(:)); [ia,it]=ind2sub(size(power),peak);
delay=(it-1)*1e9/(N*(f(2)-f(1))); angle=angles(ia);
for sweep=1:3
    dt=1e9/(N*(f(2)-f(1)));
    delay=fminbnd(@(t) -correlation(Y,f,t,angle),delay-dt,delay+dt);
    angle=fminbnd(@(a) -correlation(Y,f,delay,a),max(-90,angle-3),min(90,angle+3));
end
reference=exp(2i*pi*.45*indices*sind(angle))*exp(-2i*pi*f*delay*1e-9);
gain=reference(:)\Y(:); wave=(gain*reference(1,:)).';
end

function value=correlation(Y,f,delay,angle)
m=((0:size(Y,1)-1)'-(size(Y,1)-1)/2);
a=exp(2i*pi*.45*m*sind(angle))*exp(-2i*pi*f*delay*1e-9);
value=abs(a(:)'*Y(:))^2/numel(a);
end

function showCost(ax,Y,f,delays,angles,truthT,truthA,label)
m=((0:size(Y,1)-1)'-(size(Y,1)-1)/2);
spatial=exp(2i*pi*.45*m*sind(angles));
frequency=exp(2i*pi*f(:)*delays*1e-9);
explained=abs(spatial'*Y*frequency).^2/numel(Y);
cost=max(0,1-explained/max(norm(Y(:))^2,realmin));
cla(ax); imagesc(ax,delays,angles,cost); ax.YDir='normal'; colorbar(ax); hold(ax,'on');
plot(ax,truthT,truthA,'wx','LineWidth',2,'MarkerSize',10);
title(ax,label); xlabel(ax,'Delay (ns)'); ylabel(ax,'AoA (°)');
end


