function [fig, root, refresh] = two_path_separation_gui(parent)
% Compare five time-domain signals from one OFDM pilot symbol.
standalone = nargin==0;
if standalone
    parent = uifigure('Name','Two-path separation | 1 LOS + 1 NLOS', ...
        'Position',[80 80 1260 760],'Tag','TwoPathSeparation');
end
fig = ancestor(parent,'figure');
root = uigridlayout(parent,[5 3],'Tag','TwoPathWaveforms');
refresh = @() update();
root.RowHeight = {43,26,26,'1x','1x'};
controls = uigridlayout(root,[1 9],'Padding',[0 0 0 0],'ColumnSpacing',5);
controls.Layout.Column = [1 3];
controls.ColumnWidth = {100,60,100,60,165,60,110,60,'1x'};
uilabel(controls,'Text','Delay gap (ns)');
gap = uieditfield(controls,'numeric','Limits',[0 40],'Value',3);
uilabel(controls,'Text','Angle gap (°)');
angle = uieditfield(controls,'numeric','Limits',[0 60],'Value',40);
uilabel(controls,'Text','NLOS / LOS Power (dB)');
ratio = uieditfield(controls,'numeric','Limits',[-30 40],'Value',0);
uilabel(controls,'Text','NLOS SNR (dB)');
snr = uieditfield(controls,'numeric','Limits',[-20 70],'Value',20);
btn = uibutton(controls,'Text','Generate / Separate','Tag','RunTwoPath','ButtonPushedFcn',@update);
status = uilabel(root,'Tag','TwoPathStatus');
status.Layout.Row = 2;
status.Layout.Column = [1 3];
quality = uilabel(root,'Tag','TwoPathMetrics');
quality.Layout.Row = 3;
quality.Layout.Column = [1 3];
truthLos = waveformAxes(4,1,'True LOS');
truthNlos = waveformAxes(4,2,'True NLOS');
received = waveformAxes(4,3,'Received mixture ( blue I / orange Q)');
fitEarly = waveformAxes(5,1,'Recovered path 1 ( earlier, LOS Candidate)');
fitLate = waveformAxes(5,2,'Recovered path 2 ( later, NLOS Candidate)');
scene = makeAxes(5,3,'TwoPathScene');

bw = 80e6;
k = (-32:31).';
freq = bw*k/numel(k);
delayGrid = 0:1:64;
angleGrid = -60:5:60;
[tau, theta] = ndgrid(delayGrid,angleGrid);
n = numel(k);
oversampled = 8*n;
timeNs = (0:oversampled-1)'/bw/8*1e9;
pilotRng = RandStream('mt19937ar','Seed',42);
pilot = 2*(rand(pilotRng,n,1)>0.5)-1;
update();

    function ax = waveformAxes(row,col,label)
        ax = makeAxes(row,col,sprintf('TwoPathWaveform%d%d',row,col));
        title(ax,label);
        xlabel(ax,'Time (ns)');
        ylabel(ax,'Baseband amplitude');
        pos_plot_style(ax);
    end

    function ax = makeAxes(row,col,tag)
        box = uipanel(root,'BorderType','none');
        box.Layout.Row = row;
        box.Layout.Column = col;
        layout = uigridlayout(box,[1 1],'Padding',[0 0 0 0]);
        ax = uiaxes(layout,'Tag',tag);
    end

    function update(~,~)
        btn.Enable = 'off';
        reset = onCleanup(@() set(btn,'Enable','on'));
        status.Text = 'Fitting two paths …';
        drawnow limitrate nocallbacks;
        truth = [12 -10; 12+gap.Value -10+angle.Value];
        truthAtoms = response(truth(:,1),truth(:,2));
        noiseRng = RandStream('mt19937ar','Seed',17);
        gains = [10^(-ratio.Value/20); exp(1i*2*pi*rand(noiseRng))];
        paths = truthAtoms.*gains.';
        noise = (randn(noiseRng,n*3,1)+1i*randn(noiseRng,n*3,1))*10^(-snr.Value/20)/sqrt(2);
        observed = sum(paths,2)+noise;
        rho = abs(truthAtoms(:,1)'*truthAtoms(:,2))/(n*3);
        estimate = nan(2);
        separated = nan(n*3,2);
        if rho < 1-1e-12
            [estimate,separated] = separate(observed);
        end
        firstAntenna = [paths(1:n,:),observed(1:n),separated(1:n,:)];
        % Apply the known pilot to CSI, then synthesize the baseband symbol.
        bins = complex(zeros(oversampled,5));
        bins(mod(k,oversampled)+1,:) = pilot.*firstAntenna;
        waves = ifft(bins)*oversampled/n;
        limit = 1.05*max(abs([real(waves(:));imag(waves(:))]),[],'omitnan');
        axesList = [truthLos truthNlos received fitEarly fitLate];
        for j = 1:5
            ax = axesList(j);
            cla(ax);
            if all(isfinite(waves(:,j)))
                plot(ax,timeNs,[real(waves(:,j)),imag(waves(:,j))]);
            else
                text(ax,0.5,0.5,'The two path responses coincide, No unique decomposition', ...
                    'Units','normalized','HorizontalAlignment','center');
            end
            xlim(ax,[0 800]);
            ylim(ax,[-limit limit]);
            pos_plot_style(ax);
        end
        drawScene(truth);
        if any(~isfinite(estimate),'all')
            status.Text = sprintf('80 MHz | 3 element | Response coherence %.3f | Two paths are unidentifiable',rho);
        else
            if estimate(1,1)==estimate(2,1)
                ambiguity = '| Equal fitted delays';
            else
                ambiguity = '';
            end
            status.Text = sprintf(['80 MHz | 3 element | Response coherence %.3f |' ...
                'Fit: %.1f ns / %.0f°, %.1f ns / %.0f°%s'], ...
                rho,estimate(1,:),estimate(2,:),ambiguity);
            errorDb = 10*log10(sum(abs(waves(:,4:5)-waves(:,1:2)).^2)./sum(abs(waves(:,1:2)).^2));
            status.Text = status.Text + string(sprintf(' | NMSE %.1f / %.1f dB',errorDb));
        end
        metrics = los_quality_metrics(true,truth(1,:),estimate(1,:),waves(:,1),waves(:,4));
        quality.Text = metrics.summary;
        if all(isfinite(metrics.errors(1:2)))
            quality.Text = quality.Text + string(sprintf('  |  ToA %+.2f ns / AoA %+.2f°', ...
                metrics.errors(1),metrics.errors(2)));
        end
        root.UserData = struct('truth',truth,'estimate',estimate,'timeNs',timeNs, ...
            'waveforms',waves,'coherence',rho,'metrics',metrics);
        if standalone
            fig.UserData = root.UserData;
        end
    end

    function values = response(delays,angles)
        temporal = exp(-2i*pi*freq*delays(:).'*1e-9);
        spatial = exp(-1i*pi*(0:2).'*sind(angles(:).'));
        values = reshape(reshape(temporal,n,1,[]).*reshape(spatial,1,3,[]),n*3,[]);
    end

    function [estimate,parts] = separate(observed)
        % Keep the strongest single-path candidates, then jointly fit pairs.
        persistent dictionary
        if isempty(dictionary)
            dictionary = response(tau(:),theta(:))/sqrt(n*3);
        end
        projection = dictionary'*observed;
        [~,order] = maxk(abs(projection),180);
        % Keep plausible delays at every angle, including weak candidates.
        byAngle = reshape(abs(projection),numel(delayGrid),[]);
        [~,bestDelay] = maxk(byAngle,5,1);
        order = unique([order; reshape(bestDelay+(0:numel(angleGrid)-1)*numel(delayGrid),[],1)]);
        subset = dictionary(:,order);
        projected = projection(order);
        cross = subset'*subset;
        denom = 1-abs(cross).^2;
        valid = triu(denom>1e-10,1);
        denom(~valid) = 1;
        score = (abs(projected).^2+abs(projected.').^2 ...
            -2*real(conj(projected).*cross.*projected.'))./denom;
        score(~valid) = -Inf;
        [~,peak] = max(score(:));
        [i,j] = ind2sub(size(score),peak);
        paths = order([i;j]);
        [~,sorted] = sort(tau(paths));
        paths = paths(sorted);
        estimate = [tau(paths),theta(paths)];
        basis = dictionary(:,paths);
        parts = basis.*(basis\observed).';
    end

    function drawScene(truth)
        cla(scene);
        hold(scene,'on');
        plot(scene,[0 1],[0 0],'-o','LineWidth',2,'DisplayName','LOS');
        plot(scene,[0 0.58 1],[0 0.60 0],'-o','LineWidth',2,'DisplayName','NLOS');
        text(scene,0,-0.08,'Transmitter','HorizontalAlignment','center');
        text(scene,1,-0.08,'Receiver','HorizontalAlignment','center');
        text(scene,0.58,0.67,'Reflection point','HorizontalAlignment','center');
        text(scene,0.5,-0.2,sprintf('Truth: %.1f ns / %.0f°, %.1f ns / %.0f°', ...
            truth(1,:),truth(2,:)),'HorizontalAlignment','center');
        xlim(scene,[-0.2 1.2]);
        ylim(scene,[-0.27 0.85]);
        axis(scene,'off');
        title(scene,'Simplified scene');
        text(scene,0.24,0.05,'LOS','Color',[0 0.45 0.74]);
        text(scene,0.80,0.38,'NLOS','Color',[0.85 0.33 0.10]);
        hold(scene,'off');
    end
end
