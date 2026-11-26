function render = inf_waveform_view(parent,drawScene,rerun)
% Compare the current pilot components and their path diagnostics over the track.
layout = uigridlayout(parent,[8 3]);
layout.RowHeight = {32,36,40,35,0,'1x','1x','1x'};
summary = uilabel(layout,'Tag','FactoryWaveformSummary');
summary.Layout.Row = 2;
summary.Layout.Column = [1 3];
summary.WordWrap = 'on';
actions = uigridlayout(layout,[1 6],'Padding',[0 0 0 0]);
actions.Layout.Row = 1;
actions.Layout.Column = [1 3];
candidateButton = uibutton(actions,'Text','All OMP Candidate','Tag','OpenOmpCandidates', ...
    'Enable','off','ButtonPushedFcn',@openCandidates);
metricsButton = uibutton(actions,'Text','Track metrics','Tag','OpenLosMetrics', ...
    'Enable','off','ButtonPushedFcn',@showTrackMetrics);
diagButton = uibutton(actions,'Text','LOS Diagnostics','Tag','OpenLosGeometryDiagnostics', ...
    'Enable','off','ButtonPushedFcn',@openGeometryDiagnostics);
boundaryButton = uibutton(actions,'Text','LOS Failure boundary','Tag','OpenOmpBoundary', ...
    'Enable','off','ButtonPushedFcn',@openBoundary);
knownButton=uibutton(actions,'Text','Known LOS Experiment','Enable','off', ...
    'Tag','OpenKnownLosExperiments','ButtonPushedFcn',@openKnownLos);
observationButton=uibutton(actions,'Text','Observation contribution','Enable','off', ...
    'Tag','OpenObservationContribution','ButtonPushedFcn',@openObservation);
frameQuality = uilabel(layout,'Tag','LosFrameMetrics');
frameQuality.Layout.Row = 3;
frameQuality.Layout.Column = [1 2];
frameQuality.WordWrap = 'on';
algorithm = uidropdown(layout,'Items',{'OMP ( Earliest path)','SPRING+ (CSI adaptation)','M³ (MIMO SAGE+) ','Radio SLAM ( synchronized 2D adaptation)'}, ...
    'ItemsData',{'omp','spring','m3','radio'},'Value','omp','Tag','LosSeparationAlgorithm', ...
    'ValueChangedFcn',@changeAlgorithm);
algorithm.Layout.Row = 3;
algorithm.Layout.Column = 3;
summary.Text = 'Generate a channel to inspect frame waveforms.';
comparison = uilabel(layout,'Tag','FactoryPathComparison','Interpreter','none');
comparison.Layout.Column = [1 3];
comparison.Layout.Row = 4;
comparison.WordWrap = 'off';
settings = uigridlayout(layout,[1 1],'Padding',[0 0 0 0],'Visible','off');
settings.Layout.Row=5; settings.Layout.Column=[1 3];
options=struct('paths',8,'rounds',3,'energy',99,'meters',1,'db',3,'prior',.65);
labels = ["True LOS","True NLOS ( coherent sum of all clusters)","Noisy received ( blue I / orange Q)", ...
    "Estimate LOS Candidate","Estimate NLOS ( coherent sum of remaining candidates)","Current-frame paths"];
trendTitles = ["Received power (dBm)","Arrival angle AoA (°)","Propagation delay (ns)"];
ax = gobjects(1,9);
for tileIndex = 1:9
    tile = uipanel(layout,'BorderType','none','AutoResizeChildren','off');
    tile.Layout.Row = 6+floor((tileIndex-1)/3);
    tile.Layout.Column = 1+mod(tileIndex-1,3);
    % Equal inner rectangles keep borders aligned despite different labels.
    ax(tileIndex) = uiaxes(tile,'Units','normalized','InnerPosition',[.15 .20 .81 .68], ...
        'PositionConstraint','innerposition','Tag',sprintf('FactoryWaveform%d',tileIndex),'FontSize',13,'TitleFontSizeMultiplier',1);
    if tileIndex<=6
        title(ax(tileIndex),labels(tileIndex));
    else
        title(ax(tileIndex),trendTitles(tileIndex-6));
    end
end
render = @show;
lastFrame = NaN;
lastGeneration = NaN;
cached = [];
trendGeneration = NaN;
trendSelection = [];
cursors = gobjects(1,3);
estimateDots = gobjects(1,3);
estimateLines = gobjects(1,3);
estimateHistory = [];
estimateComputed = [];
candidateFigure = gobjects(0);
candidateCursor = gobjects(0);
currentData = [];
trackMetricsText = [];
fits = struct([]);
computed = [];
currentCluster = NaN;
currentSelection = 0;
owner = ancestor(parent,'figure');
ownerListener = addlistener(owner,'ObjectBeingDestroyed',@closeCandidates);
candidateButton.UserData = ownerListener;

    function show(data,frame,cluster,generation,clusterSelection)
        currentCluster = cluster;
        currentSelection = clusterSelection;
        if generation~=lastGeneration
            fits = struct([]);
            computed = false(size(data.time));
            closeCandidates();
            currentData = data;
            resetHistory(numel(data.time));
            trackMetricsText = [];
            metricsButton.UserData = [];
        end
        candidateButton.Enable = 'on';
        metricsButton.Enable = 'on';
        diagButton.Enable = 'on';
        boundaryButton.Enable = 'on';
        knownButton.Enable = 'on';
        observationButton.Enable = 'on';
        if ~isempty(candidateCursor) && isgraphics(candidateCursor)
            candidateCursor.Value = data.time(frame);
        end
        if generation~=lastGeneration || frame~=lastFrame
            ensureFits(frame);
            cached = recover(data,frame,false,fits,algorithm.Value);
            lastGeneration = generation;
            lastFrame = frame;
        end
        curves = cached.curves;
        limit = max(abs([real(curves(:));imag(curves(:))]));
        limit = max(1.05*limit,realmin);
        for i = 1:5
            cla(ax(i));
            if ~data.isLos && i==1
                text(ax(i),0.5,0.5,'This scene has no LOS','Units','normalized','HorizontalAlignment','center');
            else
                plot(ax(i),cached.timeNs,[real(curves(:,i)),imag(curves(:,i))]);
                pos_plot_style(ax(i));
            end
            title(ax(i),labels(i));
            xlabel(ax(i),'In-frame delay (ns)');
            ylabel(ax(i),'Baseband amplitude');
            xlim(ax(i),[0 data.unambiguousDelayS*1e9]);
            ylim(ax(i),[-limit limit]);
        end
        summary.Text = cached.message;
        frameQuality.Text = cached.metrics.summary + string(sprintf('| AoA error %+.2f°',cached.metrics.errors(2)));
        if ~isfinite(cached.metrics.errors(2))
            frameQuality.Text = cached.metrics.summary;
        end
        frameQuality.Text = frameQuality.Text+" | "+cached.stage;
        frameQuality.Tooltip = frameQuality.Text;
        drawScene(ax(6),cluster,true);
        legend(ax(6),'off');
        axis(ax(6),'normal');
        set(ax(6),'DataAspectRatioMode','auto','PlotBoxAspectRatioMode','auto');
        title(ax(6),sprintf('Current-frame paths · t = %.2f s',data.time(frame)));
        showTrends(data,frame,cluster,clusterSelection,generation);
        % Scene rendering creates a temporary legend which can move its axes.
        drawnow limitrate nocallbacks;
        set(ax,'Units','normalized','InnerPosition',[.15 .20 .81 .68], ...
            'PositionConstraint','innerposition');
    end
    function openCandidates(~,~)
        if ~isempty(candidateFigure) && isgraphics(candidateFigure)
            figure(candidateFigure);
            return
        end
        candidateButton.Enable = 'off';
        cleanup = onCleanup(@() set(candidateButton,'Enable','on'));
        ensureFits(1:numel(currentData.time));
        [candidateFigure,candidateCursor] = inf_omp_candidate_view(currentData,lastFrame,fits,algorithm.Value);
    end

    function changeAlgorithm(~,~)
        drawSettings();
        invalidate();
    end

    function invalidate()
        closeCandidates();
        fits = struct([]);
        if ~isempty(currentData), computed=false(size(currentData.time)); end
        trackMetricsText = [];
        metricsButton.UserData = [];
        candidateButton.Text = 'All OMP Candidate';
        if strcmp(algorithm.Value,'spring')
            candidateButton.Text = 'All MUSIC Candidate';
        elseif ismember(algorithm.Value,{'m3','radio'})
            candidateButton.Text = 'All candidates / Table';
        end
        if isempty(currentData)
            return
        end
        frame = lastFrame;
        lastFrame = NaN;
        resetHistory(numel(currentData.time));
        show(currentData,frame,currentCluster,lastGeneration,currentSelection);
    end

    function drawSettings()
        delete(settings.Children);
        switch algorithm.Value
            case 'm3'
                fields={'paths','rounds'}; names={'Maximum initial paths','SAGE Maximum rounds'};
                limits={[1 20],[1 20]}; integers=[true true];
                hint='3D subspace initialization · SAGE+ · earliest-path assumption';
                detail='single-band orthogonal MIMO pilots estimate AoA, AoD, Delay. GUI labels the earliest candidate as LOS, assumes a physical direct path.';
            case 'radio'
                fields={'energy','meters','db','prior'};
                names={'SVD energy (%)','Distance window (m)','Power window (dB)','LOS prior probability'};
                limits={[1 100],[0 100],[0 100],[.001 .999]}; integers=false(1,4);
                hint='dual gates + synchronized 2D geometry assumption';
                detail='Power window compares two-sided beam-probing power. Geometry cost assumes synchronized clocks, known array orientation and single-bounce reflection model ; LOS prior is this GUI assumed probability.';
            otherwise
                settings.Visible='off'; layout.RowHeight{5}=0; return
        end
        settings.Visible='on'; layout.RowHeight{5}=28;
        settings.ColumnWidth=[repmat({'fit',58},1,numel(fields)),{70,'1x'}];
        for k=1:numel(fields)
            uilabel(settings,'Text',names{k});
            e=uieditfield(settings,'numeric','Limits',limits{k},'Value',options.(fields{k}), ...
                'Tag',['LosParam_' fields{k}],'UserData',fields{k});
            if integers(k), e.RoundFractionalValues='on'; end
        end
        uibutton(settings,'Text','Apply settings','Tag','ApplyLosParams','ButtonPushedFcn',@applySettings);
        uilabel(settings,'Text',hint,'Tooltip',detail);
    end

    function applySettings(~,~)
        fields=findobj(settings,'Type','uinumericeditfield');
        for e=reshape(fields,1,[]), options.(e.UserData)=e.Value; end
        invalidate();
    end

    function ensureFits(indices)
        if strcmp(algorithm.Value,'spring') && isempty(fits)
            algorithm.Enable = 'off';
            reset = onCleanup(@() set(algorithm,'Enable','on'));
            summary.Text = 'Computing full-track SPRING+ Candidate …';
            drawnow limitrate nocallbacks;
            fits = inf_spring_plus_fit(currentData.Y,currentData.frequencyOffsetsHz, ...
                currentData.noisePerToneStd);
        elseif ismember(algorithm.Value,{'m3','radio'})
            pending=reshape(indices(~computed(indices)),1,[]);
            if numel(pending)>12
                progress=uiprogressdlg(owner,'Title','Computing multipath candidates','Message','Processing channel …');
                cleanup=onCleanup(@() delete(progress));
            end
            for j=1:numel(pending)
                index=pending(j);
                entry=inf_paper_los_fit(currentData.mimoPilot(:,:,:,index), ...
                    currentData.frequencyOffsetsHz,currentData.beamWeights(:,index), ...
                    currentData.noisePerToneStd,algorithm.Value,options);
                if isempty(fits), fits=entry([]); end
                fits(index)=entry;
                computed(index)=true;
                if numel(pending)>12
                    progress.Value=j/numel(pending);
                    progress.Message=sprintf('Processed %d / %d frames',j,numel(pending));
                    drawnow limitrate nocallbacks;
                end
            end
        end
    end

    function openGeometryDiagnostics(~,~)
        diagButton.Enable = 'off';
        resetButton = onCleanup(@() set(diagButton,'Enable','on'));
        count=numel(currentData.time);
        ensureFits(1:count);
        values=nan(count,3);
        for k=1:count
            if k==lastFrame
                result=cached;
            else
                result=recover(currentData,k,true,fits,algorithm.Value);
            end
            values(k,:)=result.losEstimate;
        end
        inf_geometry_diagnostics(currentData,values,algorithm.Value);
    end

    function openKnownLos(~,~)
        experimentData=currentData;
        if ~isfield(experimentData,'losArrayPilot')
            experimentData=rerun(currentData.parameters);
        end
        inf_known_los_view(experimentData,lastFrame);
    end

    function openObservation(~,~)
        if ~currentData.isLos
            uialert(owner,'No physical LOS: LOS-referenced observation contributions are not applicable.','Observation contribution');
            return
        end
        observationButton.Enable='off';
        restore=onCleanup(@() set(observationButton,'Enable','on'));
        ensureFits(1:numel(currentData.time));
        values=nan(numel(currentData.time),3);
        for k=1:numel(currentData.time)
            result=recover(currentData,k,true,fits,algorithm.Value);
            values(k,:)=result.losEstimate;
        end
        inf_observation_view(currentData,values,algorithm.Value,lastFrame);
    end

    function openBoundary(~,~)
        inf_omp_boundary_view(currentData,rerun,algorithm.Value,options);
    end

    function showTrackMetrics(~,~)
        if isempty(trackMetricsText)
            metricsButton.Enable = 'off';
            reset = onCleanup(@() set(metricsButton,'Enable','on'));
            metricsButton.Text = 'Computing metrics …';
            restoreText = onCleanup(@() set(metricsButton,'Text','Track metrics'));
            drawnow limitrate nocallbacks;
            count = numel(currentData.time);
            passed = zeros(1,3);
            eligible = zeros(1,3);
            template = cached.metrics;
            if currentData.isLos
                ensureFits(1:count);
                for k = 1:count
                    if k==lastFrame
                        metric = cached.metrics;
                    else
                        result = recover(currentData,k,true,fits,algorithm.Value);
                        metric = result.metrics;
                    end
                    passed = passed + metric.passed;
                    eligible = eligible + metric.eligible;
                end
            end
            names = ["LOS selection success rate","LOS waveform recovery rate","Joint success rate"];
            lines = strings(1,3);
            for k = 1:3
                if eligible(k)>0
                    lines(k) = sprintf('%s %.1f%% (%d / %d frames)', ...
                        names(k),100*passed(k)/eligible(k),passed(k),eligible(k));
                else
                    lines(k) = names(k)+"N/A ( No eligible frames)";
                end
            end
            thresholds = sprintf('Thresholds: |ToA error | ≤ %g ns, |AoA error | ≤ %g°, LOS NMSE ≤ %g dB', ...
                template.limits);
            trackMetricsText = join([lines, "",string(thresholds)],newline);
            metricsButton.UserData = struct('passed',passed,'eligible',eligible,'limits',template.limits);
        end
        uialert(owner,trackMetricsText,['Full track LOS Metrics ·' upper(algorithm.Value)],'Icon','info');
    end

    function closeCandidates(~,~)
        if ~isempty(candidateFigure) && isgraphics(candidateFigure)
            delete(candidateFigure);
        end
        candidateFigure = gobjects(0);
        candidateCursor = gobjects(0);
    end

    function resetHistory(frameCount)
        estimateHistory = nan(frameCount,3);
        estimateComputed = false(frameCount,1);
    end

    function showTrends(data,frame,cluster,selection,generation)
        time = data.time;
        estimateHistory(frame,:) = cached.losEstimate;
        estimateComputed(frame) = true;
        pending = find(~estimateComputed(1:frame)).';
        ensureFits(pending);
        for k = pending
            result = recover(data,k,true,fits,algorithm.Value);
            estimateHistory(k,:) = result.losEstimate;
        end
        estimateComputed(pending) = true;
        if trendGeneration~=generation || ~isequal(trendSelection,selection)
            frames = 1:numel(time);
            if selection==0
                clusters = data.strongestNlos;
            else
                clusters = repmat(selection,size(time));
            end
            truthLos = [data.pathDbm(1,:); data.anglesDeg(2,:); data.referenceDelayS*1e9];
            if ~data.isLos
                truthLos(:) = NaN;
            end
            truthNlos = nan(3,numel(time));
            for k = frames(isfinite(clusters))
                path = clusters(k);
                delayFrame = min(k,size(data.delayS,4));
                truthNlos(:,k) = [data.pathDbm(path,k); data.nlosClusterAnglesDeg(path,k); ...
                    1e9*data.delayS(1,1,path,delayFrame)];
            end
            for k = 1:3
                a = ax(k+6);
                cla(a);
                hold(a,'on');
                plot(a,time,truthLos(k,:),'Color',[0 0.48 0.55],'LineWidth',1.4);
                plot(a,time,truthNlos(k,:),'Color',[0.82 0.4 0.03],'LineWidth',1.4);
                if k==1
                    plot(a,time,data.totalNlosDbm,'--','Color',[0.42 0.47 0.54]);
                end
                cursors(k) = xline(a,time(frame),':k');
                estimateLines(k) = plot(a,NaN,NaN,'.-','Color',[0.49 0.24 0.69], ...
                    'LineWidth',1.3,'MarkerSize',7,'Tag',sprintf('LosEstimateTrail%d',k));
                estimateDots(k) = plot(a,NaN,NaN,'d','Color',[0.49 0.24 0.69], ...
                    'MarkerFaceColor',[0.49 0.24 0.69],'MarkerSize',5);
                xlim(a,time([1 end]));
                pos_plot_style(a);
                xlabel(a,'Track time (s)');
                title(a,trendTitles(k));
                hold(a,'off');
            end
            trendGeneration = generation;
            trendSelection = selection;
        end
        for k = 1:3
            cursors(k).Value = time(frame);
            set(estimateLines(k),'XData',time(1:frame),'YData',estimateHistory(1:frame,k));
            set(estimateDots(k),'XData',time(frame),'YData',cached.losEstimate(k));
        end

        key = 'LOS truth | NLOS reference | dashed: total NLOS | markers: LOS candidate';
        if isfinite(cluster)
            clusterLabel = sprintf('| reference cluster #%d',cluster);
        else
            clusterLabel = '| No NLOS reference cluster';
        end
        delta = '';
        if data.isLos && isfinite(cluster)
            delayFrame = min(frame,size(data.delayS,4));
            delta = sprintf(' | NLOS−LOS: %+.1f dB, %+.1f°, %+.2f ns', ...
                data.pathDbm(cluster,frame)-data.pathDbm(1,frame), ...
                data.nlosClusterAnglesDeg(cluster,frame)-data.anglesDeg(2,frame), ...
                1e9*(data.delayS(1,1,cluster,delayFrame)-data.referenceDelayS(frame)));
        end
        comparison.Text = [key clusterLabel delta];
    end
end

function out = recover(data,frame,metricsOnly,fits,method)
received = data.Y(:,:,frame);
frequency = data.frequencyOffsetsHz;
if ~strcmp(method,'omp')
    fit = fits(frame);
    parts = fit.parts;
    delays = fit.delays;
    angles = fit.angles;
    selected = fit.los;
else
    [parts,delays,angles] = inf_waveform_fit(received,frequency,data.noisePerToneStd);
    selected = double(~isempty(delays));
end
los = data.losPilotFirstRx(:,frame);
losFit = zeros(size(los));
out.losEstimate = [NaN NaN NaN];
if selected>0
    losFit = parts(:,selected);
    out.losEstimate = [10*log10(sum(abs(losFit).^2)), angles(selected), 1e9*delays(selected)];
end
truthParams = [1e9*data.referenceDelayS(frame),data.anglesDeg(2,frame)];
out.metrics = los_quality_metrics(data.isLos,truthParams,out.losEstimate([3 2]),los,losFit);
if metricsOnly
    return
end
% Post-decision diagnostics only. The estimator has already returned.
matches = abs(delays*1e9-truthParams(1))<=out.metrics.limits(1) & ...
    abs(mod(angles-truthParams(2)+180,360)-180)<=out.metrics.limits(2);
if ~data.isLos
    out.stage = "No physical LOS truth";
elseif out.metrics.passed(3)
    out.stage = "Path identification and waveform recovery pass";
elseif out.metrics.passed(1)
    out.stage = "Parameter match, waveform recovery fails";
elseif strcmp(method,'spring') && frame<3
    out.stage = "SPRING+ warm-up, insufficient history 3 frames";
elseif ~any(matches)
    out.stage = "No candidate matches the truth window";
elseif strcmp(method,'radio') && ~any(fit.eligible(matches))
    out.stage = "Matching candidate rejected by distance or power gate";
elseif selected==0
    out.stage = "Matching candidate exists, estimator does not report LOS";
else
    out.stage = "Matching candidate exists, estimator selects a different path";
end
nlos = data.pilot*data.H(1,:,frame).'-los;
nlosFit = sum(parts(:,(1:numel(delays))~=selected),2);
n = numel(frequency);
nFFT = 4*2^nextpow2(n);
bins = mod(-floor(n/2):ceil(n/2)-1,nFFT)+1;
padded = complex(zeros(nFFT,5));
padded(bins,:) = [los,nlos,received(1,:).',losFit,nlosFit];
out.curves = ifft(padded)*nFFT/n;
out.timeNs = (0:nFFT-1)'*data.unambiguousDelayS/nFFT*1e9;
nlosText = nmseText(nlos,nlosFit);
if data.isLos
    losText = '—';
    if selected>0 && out.metrics.eligible(2)
        losText = sprintf('%.1f dB',out.metrics.errors(3));
    end
    if selected>0
        toaText = sprintf('%+.2f ns',1e9*(delays(selected)-data.referenceDelayS(frame)));
    else
        toaText = 'Not detected';
    end
    out.message = sprintf('Fit %d paths | LOS Candidate ToA error %s | LOS NMSE %s | NLOS NMSE %s', ...
        numel(delays),toaText,losText,nlosText);
else
    out.message = sprintf('No true LOS | Candidate %d | Estimator output LOS: %s | NLOS NMSE %s', ...
        numel(delays),string(selected>0),nlosText);
end
if ismember(method,{'m3','radio'})
    out.message = string(out.message)+" | "+fit.reason;
end
end

function label = nmseText(truth,estimate)
energy = sum(abs(truth).^2);
if energy==0
    label = '—';
else
    label = sprintf('%.1f dB',10*log10(sum(abs(estimate-truth).^2)/energy));
end
end


