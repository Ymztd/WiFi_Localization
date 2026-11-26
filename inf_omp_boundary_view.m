function fig=inf_omp_boundary_view(base,rerun,initialMethod,options)
% Interactive InF sweep. Each level regenerates a QuaDRiGa channel and OMP fit.
if nargin<3, initialMethod='omp'; end
if nargin<4, options=struct('paths',8,'rounds',3,'energy',99,'meters',1,'db',3,'prior',.65); end
fig=uifigure('Name','LOS Failure boundary · InF Scene','Position',[65 55 1500 900]);
root=uigridlayout(fig,[4 3]); root.RowHeight={38,45,'1x','0.9x'};
titleLabel=uilabel(root,'Text',['LOS Failure boundary |' char(base.scenario)],'FontSize',20,'FontWeight','bold');
titleLabel.Layout.Column=[1 2];
method=uidropdown(root,'Items',{'OMP','SPRING+','M³','Radio SLAM'}, ...
 'ItemsData',{'omp','spring','m3','radio'},'Value',initialMethod,'Tag','BoundaryMethod', ...
 'ValueChangedFcn',@runSweep);
method.Layout.Row=1; method.Layout.Column=3;
controls=uigridlayout(root,[1 7],'Padding',[0 0 0 0]); controls.Layout.Row=2; controls.Layout.Column=[1 3];
uilabel(controls,'Text','Control variable');
variable=uidropdown(controls,'Items',{'Bandwidth MHz','Antennas','LOS attenuation dB','TX beam center °'}, ...
 'ItemsData',{'bandwidth','array','block','beam'},'Value','bandwidth','ValueChangedFcn',@runSweep);
runButton=uibutton(controls,'Text','Run current InF Scan','ButtonPushedFcn',@runSweep);
uilabel(controls,'Text','Current level');
level=uidropdown(controls,'Items',{'Not run'},'Enable','off','ValueChangedFcn',@drawLevel);
uilabel(controls,'Text','Current frame');
frame=uislider(controls,'Limits',[1,numel(base.time)],'Value',1,'MajorTicks',[], ...
 'ValueChangedFcn',@drawLevel,'ValueChangingFcn',@frameMoving);
axesPower=uiaxes(root); axesAngle=uiaxes(root); axesDelay=uiaxes(root);
lower=uigridlayout(root,[2 3],'Padding',[0 0 0 0]); lower.Layout.Row=4; lower.Layout.Column=[1 3];
lower.RowHeight={'1x',28};
axesRate=uiaxes(lower); axesCandidate=uiaxes(lower); axesMap=uiaxes(lower);
status=uilabel(lower,'Text','Select a control variable and run. All levels use the same scene and random seed.');
status.Layout.Row=2; status.Layout.Column=[1 3];
results=struct([]); values=[];
    function frameMoving(~,event)
        frame.Value=round(event.Value); drawLevel();
    end
    function runSweep(~,~)
        p=base.parameters; key=variable.Value;
        switch key
            case 'bandwidth', values=[20 40 80 120 195.84];
            case 'array', values=[2 3 4 6 8];
            case 'block', values=[0 5 10 20 30];
            case 'beam', values=[-60 -30 0 30 60];
        end
        nextResults=repmat(struct('data',[],'est',[],'candidate',[], ...
            'correct',[],'count',[]),1,numel(values));
        runButton.Enable='off'; level.Enable='off';
        method.Enable='off'; variable.Enable='off'; frame.Enable='off';
        reset=onCleanup(@() unlock());
        progress=uiprogressdlg(fig,'Title','InF Controlled experiment','Message','Generate channel and run Estimate …');
        closeProgress=onCleanup(@() delete(progress));
        results=struct([]);
        for tile=[axesPower axesAngle axesDelay axesRate axesCandidate axesMap], cla(tile); end
        status.Text='Computing configuration';
        for j=1:numel(values)
            q=p; v=values(j);
            switch key
                case 'bandwidth'
                    q.bwMHz=v;
                    q.tones=max(p.tones,ceil(p.tones*v/p.bwMHz));
                case 'array', q.nRx=v; q.nTx=v;
                case 'block', q.useBox=true; q.boxLoss=v;
                case 'beam', q.beam=[v v]; q.scanMode='manual';
            end
            progress.Value=(j-1)/numel(values); progress.Message=sprintf('%d / %d, Parameter %.2f',j,numel(values),v);
            drawnow limitrate;
            d=rerun(q); n=numel(d.time);
            est=nan(n,3); candidate=false(n,1); count=zeros(n,1);
            if strcmp(method.Value,'spring')
                history=inf_spring_plus_fit(d.Y,d.frequencyOffsetsHz,d.noisePerToneStd);
            end
            for k=1:n
                if strcmp(method.Value,'omp')
                    [parts,t,a]=inf_waveform_fit(d.Y(:,:,k),d.frequencyOffsetsHz,d.noisePerToneStd);
                    pick=double(~isempty(t));
                else
                    if strcmp(method.Value,'spring')
                        fit=history(k);
                    else
                        fit=inf_paper_los_fit(d.mimoPilot(:,:,:,k),d.frequencyOffsetsHz, ...
                            d.beamWeights(:,k),d.noisePerToneStd,method.Value,options);
                    end
                    parts=fit.parts; t=fit.delays; a=fit.angles; pick=fit.los;
                end
                count(k)=numel(t);
                if isempty(t), continue; end
                if pick>0, est(k,:)=[10*log10(sum(abs(parts(:,pick)).^2)),a(pick),t(pick)*1e9]; end
                candidate(k)=any(abs(t*1e9-d.referenceDelayS(k)*1e9)<=1 & ...
                    abs(a-d.anglesDeg(2,k))<=3);
            end
            truthT=d.referenceDelayS(:)*1e9; truthA=d.anglesDeg(2,:).';
            correct=abs(est(:,3)-truthT)<=1 & abs(est(:,2)-truthA)<=3;
            d=rmfield(d,{'Y','H','Hhat','mimoPilot','clusterCoefficients'});
            nextResults(j)=struct('data',d,'est',est,'candidate',candidate,'correct',correct,'count',count);
        end
        results=nextResults;
        level.Items=compose('%.2f',values); level.Value=level.Items{1}; level.Enable='on';
        frame.Limits=[1,numel(results(1).data.time)]; frame.Value=1;
        drawLevel();
    end
    function unlock()
        if isvalid(fig), runButton.Enable='on'; method.Enable='on'; variable.Enable='on'; frame.Enable='on'; end
    end
    function drawLevel(~,~)
        if isempty(results), return; end
        j=find(strcmp(level.Value,level.Items),1); if isempty(j), j=1; end
        r=results(j); d=r.data; n=numel(d.time); k=max(1,min(n,round(frame.Value)));
        truthP=d.pathDbm(1,:); nlosP=max(d.pathDbm(2:end,:),[],1);
        truthA=d.anglesDeg(2,:); truthT=d.referenceDelayS*1e9;
        plotTrack(axesPower,d.time,truthP,nlosP,r.est(:,1).',k,'Received power (dBm)');
        plotTrack(axesAngle,d.time,truthA,d.anglesDeg(3,:),r.est(:,2).',k,'Arrival angle AoA (°)');
        otherT=nan(1,n);
        for z=1:n
            q=d.strongestNlos(z);
            if isfinite(q), otherT(z)=1e9*d.delayS(1,1,q,z); end
        end
        plotTrack(axesDelay,d.time,truthT,otherT,r.est(:,3).',k,'Propagation delay (ns)');
        cla(axesRate); hold(axesRate,'on');
        cand=arrayfun(@(x) mean(x.candidate)*100,results);
        pass=arrayfun(@(x) mean(x.correct)*100,results);
        plot(axesRate,values,cand,'o-','LineWidth',1.6,'DisplayName','LOS candidate availability');
        plot(axesRate,values,pass,'s-','LineWidth',1.6,'DisplayName','Correct selection rate');
        xline(axesRate,values(j),':k'); ylim(axesRate,[0 105]); pos_plot_style(axesRate);
        xlabel(axesRate,variable.Items{find(strcmp(variable.Value,variable.ItemsData),1)}); ylabel(axesRate,'Fraction of frames (%)');
        title(axesRate,'Failure boundary and candidate stage'); legend(axesRate,'Location','best');
        cla(axesCandidate); hold(axesCandidate,'on');
        plot(axesCandidate,d.time,r.count,'Color',[.4 .4 .4],'DisplayName','Total candidates');
        scatter(axesCandidate,d.time(r.candidate),r.count(r.candidate),24,[.1 .55 .7],'filled','DisplayName','contains true LOS Candidate');
        scatter(axesCandidate,d.time(r.correct),r.count(r.correct),30,[.1 .6 .25],'filled','DisplayName','Correct selection');
        xline(axesCandidate,d.time(k),':k'); pos_plot_style(axesCandidate);
        xlabel(axesCandidate,'Track time (s)'); title(axesCandidate,'Candidate availability and final selection'); legend(axesCandidate,'Location','best');
        cla(axesMap); hold(axesMap,'on');
        plot(axesMap,d.ue(1,:),d.ue(2,:),'k-','DisplayName','UE True track');
        scatter(axesMap,d.ue(1,r.correct),d.ue(2,r.correct),28,[.1 .6 .25],'filled','DisplayName','Correct selection');
        miss=~r.correct; scatter(axesMap,d.ue(1,miss),d.ue(2,miss),28,[.85 .2 .15],'filled','DisplayName','Final failure');
        plot(axesMap,d.ue(1,k),d.ue(2,k),'kd','MarkerFaceColor','y','HandleVisibility','off');
        pos_plot_style(axesMap); axis(axesMap,'equal'); xlabel(axesMap,'x (m)'); ylabel(axesMap,'y (m)');
        title(axesMap,'UE Failure locations on the track'); legend(axesMap,'Location','best');
        stage='Not detected LOS Candidate';
        if r.candidate(k), stage='Has LOS candidate exists but wrong selection'; end
        if r.candidate(k) && ~isfinite(r.est(k,3)), stage='Matching candidate exists, estimator does not confirm LOS'; end
        if r.correct(k), stage='LOS Correct selection'; end
        status.Text=sprintf('%s | Level %.2f | t=%.2f s | %s | LOS Candidate %d/%d, Correct selection %d/%d', ...
            char(d.scenario),values(j),d.time(k),stage,nnz(r.candidate),n,nnz(r.correct),n);
    end
end
function plotTrack(ax,time,truth,other,estimate,k,label)
cla(ax); hold(ax,'on');
plot(ax,time,truth,'Color',[0 .48 .55],'LineWidth',1.5,'DisplayName','LOS Truth');
plot(ax,time,other,'Color',[.82 .4 .03],'LineWidth',1.3,'DisplayName','Strongest NLOS');
plot(ax,time,estimate,'Color',[.49 .24 .69],'LineWidth',1.3,'DisplayName','Selected candidate');
xline(ax,time(k),':k'); pos_plot_style(ax); xlim(ax,time([1 end]));
xlabel(ax,'Track time (s)'); ylabel(ax,label); title(ax,label); legend(ax,'Location','best');
end

