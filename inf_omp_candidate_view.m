function [fig,cursor] = inf_omp_candidate_view(data,currentFrame,fits,method)
% Plot the same delay-sorted candidates used to build the waveform view.
if nargin<4
    method = 'omp';
end
isOmp = strcmp(method,'omp');
paper = ismember(method,{'m3','radio'});
methodName = 'OMP';
if strcmp(method,'spring')
    methodName = 'MUSIC';
elseif strcmp(method,'m3')
    methodName = 'M³ SAGE+';
elseif strcmp(method,'radio')
    methodName = 'Radio SLAM';
end
nFrames = numel(data.time);
rows = cell(nFrames,1);
details = cell(nFrames,1);
chosen = nan(nFrames,1);
for frame = 1:nFrames
    if ~isOmp
        fit = fits(frame);
        parts = fit.parts;
        delay = fit.delays;
        angle = fit.angles;
        selected = fit.los;
        order = nan(size(delay));
    else
        [parts,delay,angle,order] = inf_waveform_fit( ...
            data.Y(:,:,frame),data.frequencyOffsetsHz,data.noisePerToneStd);
        selected = double(~isempty(delay));
    end
    count = numel(delay);
    power = 10*log10(max(sum(abs(parts).^2,1),realmin));
    rows{frame} = [repmat(data.time(frame),count,1),delay(:)*1e9, ...
        power(:),angle(:),order(:)];
    if selected>0
        chosen(frame) = delay(selected)*1e9;
    end
    if paper
        inWindow=nan(count,1); nmse=nan(count,1);
        if data.isLos && count>0
            delta=mod(angle(:)-data.anglesDeg(2,frame)+180,360)-180;
            inWindow=abs((delay(:)-data.referenceDelayS(frame))*1e9)<=1 & abs(delta)<=3;
            truth=data.losPilotFirstRx(:,frame);
            if norm(truth)>0
                nmse=10*log10(sum(abs(parts-truth).^2,1).'/sum(abs(truth).^2));
            end
        end
        details{frame} = [repmat(data.time(frame),count,1),(1:count).',delay(:)*1e9, ...
            angle(:),fit.departure(:),power(:),fit.power(:),fit.eligible(:), ...
            fit.cost(:),repmat(fit.nullCost,count,1),inWindow,nmse,(1:count).'==selected];
        if count==0
            details{frame}=[data.time(frame),0,nan(1,10),0];
        end
    end
end
points = vertcat(rows{:});

fig = figure('Name','All'+string(methodName)+'Candidate ·'+string(data.scenario),'NumberTitle','off', ...
    'Color','white','Position',[100 130 1080 620],'Tag','OmpCandidateFigure');
if paper
    tabs=uitabgroup(fig);
    plotTab=uitab(tabs,'Title','Track');
    tableTab=uitab(tabs,'Title','Frame candidate table');
    headers={'Time (s)','Path index','Delay (ns)','AoA (°)','AoD (°)','Current beam (dBm)', ...
        'Probing power (dBm)','Passes both gates','LOS cost','No LOS cost','Truth-window match','LOS NMSE (dB)','Selected as LOS'};
    values=vertcat(details{:});
    if strcmp(method,'m3')
        cols=[1:7 11:13]; headers=headers(cols); values=values(:,cols);
    end
    uitable(tableTab,'Data',values,'ColumnName',headers,'RowName',[], ...
        'Units','normalized','Position',[0 0 1 1],'Tag','PaperPathTable');
    ax=axes(plotTab);
else
    ax=axes(fig);
end
hold(ax,'on');
dots = scatter(ax,points(:,1),points(:,2),22,points(:,3),'filled', ...
    'DisplayName',[methodName 'Candidate'],'Tag','OmpCandidatePoints');
if ~isempty(points)
    dots.DataTipTemplate.DataTipRows = [ ...
        dataTipTextRow('Track time (s)',points(:,1),'%.3f'); ...
        dataTipTextRow('Estimated delay (ns)',points(:,2),'%.2f'); ...
        dataTipTextRow('Fitted power (dBm)',points(:,3),'%.1f'); ...
        dataTipTextRow('Estimate AoA (°)',points(:,4),'%.1f')];
    if isOmp
        dots.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow('OMP addition round',points(:,5),'%.0f');
    end
end
if data.isLos
    plot(ax,data.time,1e9*data.referenceDelayS,'-','Color',[0 0.40 0.42], ...
        'LineWidth',1.6,'DisplayName','True LOS Delay');
end
scatter(ax,data.time,chosen,55,'o','MarkerEdgeColor',[0.68 0.18 0.27], ...
    'LineWidth',1.2,'DisplayName','GUI selected LOS Candidate','Tag','OmpChosenLos');
cursor = xline(ax,data.time(currentFrame),':k','Current frame','HandleVisibility','off','Tag','OmpCurrentFrame');
pos_plot_style(ax);
xlim(ax,data.time([1 end]));
xlabel(ax,'Track time (s)');
ylabel(ax,'Candidate delay (ns)');
title(ax,{['All' methodName 'Candidate'],'Select a candidate to inspect AoA and power'});
if ~isempty(points)
    color = colorbar(ax);
    color.Label.String = 'Fitted power at RX element 1 (dBm)';
else
    text(ax,0.5,0.5,'No candidates detected in any frame','Units','normalized','HorizontalAlignment','center');
end
legend(ax,'Location','best');
hold(ax,'off');
end
