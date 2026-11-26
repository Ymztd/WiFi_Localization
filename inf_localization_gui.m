function fig = inf_localization_gui(configDir,quadrigaDir,parent,experimentMode)
%INF_LOCALIZATION_GUI Inspect QuaDRiGa channels along one adjustable UE track.
if nargin<1 || isempty(configDir)
    configDir = fullfile(fileparts(mfilename('fullpath')),'config');
end
if nargin<2 || isempty(quadrigaDir)
    quadrigaDir = 'D:/biye/code_f/env2024-main (1)/env2024-main/quadriga_src';
end
if nargin<4, experimentMode='3gpp'; end
isSpecular=strcmp(experimentMode,'specular');
standalone=nargin<3 || isempty(parent);
if standalone
    parent=uifigure('Name','LOS channel experiments','Position',[40 70 1500 880]);
end
fig=ancestor(parent,'figure');
root=uigridlayout(parent,[3 3]);
root.ColumnWidth = {370,'1x','1x'};
root.RowHeight = {39,'1x','1x'};
titleLabel = uilabel(root,'Text','QuaDRiGa Factory localization | UE Track and multipath','FontSize',22,'FontWeight','bold');
titleLabel.Layout.Column = [1 2];
viewButton = uibutton(root,'Text','Waveform recovery','Tag','FactoryWaveformToggle', ...
    'Enable','off','ButtonPushedFcn',@toggleWaveforms);
viewButton.Layout.Row = 1;
viewButton.Layout.Column = 3;
panel = uipanel(root,'Title','Simulation settings');
panel.Layout.Row = [2 3];
panel.Layout.Column = 1;
control = uigridlayout(panel,[10 1]);
control.RowHeight = {22,29,30,30,'1x',30,35,55,35,45};
uilabel(control,'Text','Experiment scenario');
scenarioMenu = uidropdown(control,'Tag','ScenarioMenu','ValueChangedFcn',@selectFactory);
files = uigridlayout(control,[1 2],'Padding',[0 0 0 0]);
uibutton(files,'Text','Configuration folder …','ButtonPushedFcn',@chooseConfig);
uibutton(files,'Text','QuaDRiGa folder …','ButtonPushedFcn',@chooseQuaDRiGa);
uilabel(control,'Text','Coordinates: x y z, double-click values to edit','FontColor',[0.34 0.37 0.42]);
tabs = uitabgroup(control);
setup = uitab(tabs,'Title','Scene and radio');
policyTab=uitab(tabs,'Title','Factory link');
policyGrid=uigridlayout(policyTab,[4 1]); policyGrid.RowHeight={22,30,85,'1x'};
uilabel(policyGrid,'Text','Track link condition');
linkMenu=uidropdown(policyGrid,'Items',{'LOS','NLOS','Auto'},'Tag','FactoryLink', ...
    'ValueChangedFcn',@switchScenario);
factoryInfo=uilabel(policyGrid,'WordWrap','on');
uilabel(policyGrid,'Text','Auto draws one native link state at the track start and keeps it for the track.', ...
    'WordWrap','on','VerticalAlignment','top');
box = uitab(tabs,'Title','Box attenuation');
scanTab = uitab(tabs,'Title','Beam');
s = uigridlayout(setup,[1 1],'Padding',[3 3 3 3]);
radio = uitable(s,'ColumnName',{'Parameter','Value'},'ColumnEditable',[false true], ...
    'ColumnWidth',{169,'auto'},'Tag','RadioParameters','Data',{ ...
    'BS Position (m)','0 0 8';'UE Start (m)','16 -2 1.5';'UE End (m)','16 2 1.5'; ...
    'Carrier (GHz)','28';'Bandwidth (MHz)','195.84';'Tones','513'; ...
    'BS / UE Antennas','8 8';'Total TX power (dBm)','20';'UE Noise figure (dB)','7'; ...
    'BS Manual scan angles (°)','-45 45';'Track duration (s)','4';'Frames','81';'Random seed','723'; ...
    'AoA error warning tolerance (°)','5'});
scanControls = uigridlayout(scanTab,[5 1]);
scanControls.RowHeight = {22,30,24,28,'1x'};
uilabel(scanControls,'Text','BS Beam scan mode');
scanMenu = uidropdown(scanControls,'Items',{'Round trip: LOS → NLOS → LOS','One-way: LOS → NLOS','Manual start/end'}, ...
    'ItemsData',{'return','outbound','manual'},'Value','manual','Tag','ScanMode');
uilabel(scanControls,'Text','BS element rotation about x axis roll (°), UE remains vertical');
txRoll=uieditfield(scanControls,'numeric','Limits',[-90 90],'Value',0,'Tag','TxElementRoll');
uilabel(scanControls,'Text','Manual scan uses start/end angles only. Automatic scan is a simulation control, uses path ground truth. Rotation changes TX polarization and element pattern, element positions stay fixed.', ...
    'VerticalAlignment','top','WordWrap','on');
b = uigridlayout(box,[3 1]);
b.RowHeight = {30,135,'1x'};
useBox = uicheckbox(b,'Text','Enable box attenuation','Value',false);
boxSettings = uitable(b,'ColumnName',{'Parameter','Value'},'ColumnEditable',[false true], ...
    'ColumnWidth',{142,'auto'},'Data',{ ...
    'Box center (m)','8 -0.6 2.5';'Length width height (m)','1 1.5 5';'LOS extra loss (dB)','20'});
uilabel(b,'Text','Extra loss applies only to direct rays crossing the box. Loss can be calibrated from measurements.', ...
    'VerticalAlignment','top','WordWrap','on');
clusterMenu = uidropdown(control,'Items',{'NLOS: Frame-wise strongest cluster'},'ItemsData',0,'Enable','off', ...
    'Tag','NlosDisplay','ValueChangedFcn',@refreshClusterDisplay);
runButton = uibutton(control,'Text','Generate / Update channel','Tag','GenerateChannel', ...
    'FontWeight','bold','ButtonPushedFcn',@generate);
sliderFrame = uigridlayout(control,[2 1],'Padding',[0 0 0 0]);
sliderFrame.RowHeight = {18,'1x'};
readout = uilabel(sliderFrame,'Text','Time');
slider = uislider(sliderFrame,'Limits',[1 81],'MajorTicks',[],'Enable','off');
slider.ValueChangingFcn = @(~,e) seek(e.Value);
slider.ValueChangedFcn = @(~,e) seek(e.Value);
buttons = uigridlayout(control,[1 4],'Padding',[0 0 0 0]);
play = uibutton(buttons,'Text','Play','Enable','off','ButtonPushedFcn',@startPlayback);
pauseButton = uibutton(buttons,'Text','Pause','Enable','off','ButtonPushedFcn',@pausePlayback);
saveButton = uibutton(buttons,'Text','Export.mat','Enable','off','ButtonPushedFcn',@saveData);
powerButton = uibutton(buttons,'Text','Export power','Enable','off','ButtonPushedFcn',@savePower);
status = uilabel(control,'Text','Set parameters, then generate a channel.','Tooltip',configDir);
status.WordWrap='on';

sceneTabs = tabPanel(root,2,2,@refreshFrame);
sceneAx = tabAxes(sceneTabs,'3D scene','Scene');
topAx = tabAxes(sceneTabs,'Top-view track','TopView');
powerTabs = tabPanel(root,2,3,@refreshFrame);
powerAx = tabAxes(powerTabs,'Power over time','Power');
clusterAx = tabAxes(powerTabs,'Per-cluster power','ClusterPower');
delayTabs = tabPanel(root,3,2,@refreshFrame);
delayAx = tabAxes(delayTabs,'Delay profile','Delay');
cleanAx = tabAxes(delayTabs,'Noise-free check','CleanDelay');
waterfallAx = tabAxes(delayTabs,'Delay over time','DelayHistory');
results = tabPanel(root,3,3,@refreshFrame);
angleAx = tabAxes(results,'Principal direction','Angle');
angleCheckAx = tabAxes(results,'AoA Check','AngleCheck');
rangeAx = tabAxes(results,'ToA Ranging','Range');
channelAx = tabAxes(results,'UE Receive matrix','Channel');
teal = [0 0.48 0.55];
orange = [0.82 0.4 0.03];
purple = [0.26 0.20 0.56];
red = [0.76 0.18 0.21];

% Controlled reflection parameters use the same observation/plot pipeline.
reflectionTab=uitab(tabs,'Title','Reflections');
reflectionGrid=uigridlayout(reflectionTab,[1 1]);
reflectionSettings=uitable(reflectionGrid,'ColumnName',{'Parameter','Value'}, ...
    'ColumnEditable',[false true],'ColumnWidth',{205,'auto'},'Data',{ ...
    'Side-wall offset (m)','2';'Reflection magnitude','0.8';'LOS extra loss (dB)','0'});
if isSpecular
    titleLabel.Text='Specular multipath | geometry, power and recovery';
    radio.Data{1,2}='0 0 1.5'; radio.Data{2,2}='16 -0.12 1.5'; radio.Data{3,2}='16 0.12 1.5';
    radio.Data{4,2}='5.2'; radio.Data{5,2}='80'; radio.Data{6,2}='257';
    radio.Data{7,2}='6 6'; radio.Data{10,2}='0 0'; radio.Data{11,2}='2'; radio.Data{12,2}='21';
    tabs.SelectedTab=reflectionTab;
    files.Visible='off'; txRoll.Enable='off'; scanMenu.Value='manual'; scanMenu.Enable='off';
    delete(policyTab);
else
    delete(reflectionTab);
end

factoryPanel = [];
renderWaveforms = [];
waveMode = false;
generation = 0;
originalViews = [sceneTabs powerTabs delayTabs results];
data = [];
frame = 1;
historyCursor = [];
clock = timer('ExecutionMode','fixedSpacing','Period',0.17, ...
    'TimerFcn',@advance,'StopFcn',@playbackStopped);
% The shared studio owns all stage timers; standalone windows own theirs.
timers=getappdata(fig,'PosGuiTimers');
setappdata(fig,'PosGuiTimers',[timers clock]);
if standalone, fig.DeleteFcn=@(~,~) delete(clock); end
loadScenarios();
title(sceneAx,'BS, UE and moving track');
title(powerAx,'Per-path received power');
title(delayAx,'Delay response');
title(angleAx,'Principal direction and geometric reference');

    function chooseConfig(~,~)
        folder = uigetdir(configDir,'Select.conf folder');
        if ischar(folder)
            configDir = folder;
            loadScenarios();
        end
    end

    function chooseQuaDRiGa(~,~)
        folder = uigetdir(quadrigaDir,'Select QuaDRiGa of quadriga_src folder');
        if ischar(folder)
            quadrigaDir = folder;
            status.Text = 'Selected QuaDRiGa folder.';
            status.Tooltip = quadrigaDir;
        end
    end

    function loadScenarios()
        if isSpecular
            scenarioMenu.Items={'LOS + one side wall','LOS + two side walls','LOS + two walls + floor'};
            scenarioMenu.ItemsData={'Specular_1','Specular_2','Specular_3'};
            scenarioMenu.Value='Specular_1';
            status.Text='Deterministic image-source reflections; no QuaDRiGa required.';
            return
        end
        ids={'InF-SL','InF-SH','InF-DL','InF-DH','InF-HH'};
        previous=scenarioMenu.Value;
        scenarioMenu.Items=ids;
        if ismember(string(previous),string(ids)), scenarioMenu.Value=previous; end
        selectFactory();
    end

    function selectFactory(~,~)
        if ~isSpecular
            f=inf_factory_preset(scenarioMenu.Value);
            rows=radio.Data;
            heights=[f.bsHeightM f.utHeightM f.utHeightM];
            for i=1:3
                xy=sscanf(rows{i,2},'%f',2);
                if numel(xy)==2, rows{i,2}=sprintf('%g %g %g',xy(1),xy(2),heights(i)); end
            end
            radio.Data=rows;
            if strcmp(f.id,'InF-HH')
                linkMenu.Items={'LOS'};
            else
                linkMenu.Items={'LOS','NLOS','Auto'};
            end
            factoryInfo.Text=sprintf('%s | Hall %g x %g x %g m | Clutter %.0f%%, height %g m, size %g m', ...
                f.id,f.hallM(1),f.hallM(2),f.hallM(3),100*f.density,f.clutterHeightM,f.sizeM);
            status.Text=factoryInfo.Text;
        end
        switchScenario();
    end

    function switchScenario(~,~)
        pausePlayback();
        syncFactoryView();
        if ~isempty(data)
            ready = viewButton.Enable;
            set([play saveButton powerButton],'Enable',ready);
            slider.Enable = ready;
            clusterMenu.Enable = ready;
            if strcmp(ready,'on')
                showFrame(frame);
                status.Text = "Current channel:"+erase(string(data.parameters.scenario),"3GPP_38.901_");
            elseif ~isempty(scenarioMenu.Items)
                status.Text = "Displayed scene:"+erase(string(data.parameters.scenario),"3GPP_38.901_")+", generate the selected scene.";
            end
        end
    end

    function generate(~,~)
        pausePlayback();
        runButton.Enable = 'off';
        cleanup = onCleanup(@() set(runButton,'Enable','on'));
        status.Text = 'Generating QuaDRiGa Channel …';
        drawnow limitrate nocallbacks;
        try
            p = readSettings();
            next = inf_channel_run(p,configDir,quadrigaDir);
            p=next.parameters;
        catch exception
            status.Text = 'Generation failed. See details.';
            uialert(fig,exception.message,'QuaDRiGa Simulation');
            return
        end
        data = next;
        generation = generation+1;
        delete(allchild(waterfallAx));
        historyCursor = [];
        fig.UserData = data;
        clusters = 2:size(data.pathDbm,1);
        clusterMenu.Items = cellstr(["NLOS: Frame-wise strongest cluster" "NLOS: Track cluster #"+clusters]);
        clusterMenu.ItemsData = [0 clusters];
        clusterMenu.Value = 0;
        clusterMenu.Enable = 'on';
        slider.Limits = [1 p.frames];
        slider.Value = 1;
        slider.Enable = 'on';
        play.Enable = 'on';
        saveButton.Enable = 'on';
        powerButton.Enable = 'on';
        status.Text = compose("%s | %d LOS + %d NLOS clusters", ...
            erase(string(p.scenario),"3GPP_38.901_"),double(data.isLos),size(data.pathDbm,1)-1);
        if data.addedLos
            status.Text = status.Text + "( added physical LOS)";
        end
        status.Tooltip = compose("Selected factory: %s | QuaDRiGa base profile: %s", ...
            erase(string(p.scenario),"3GPP_38.901_"),erase(data.scenario,"3GPP_38.901_"));
        if data.addedLos && ~strcmp(p.scanMode,'manual')
            status.Tooltip = status.Tooltip + "| NLOS base profile uses manual beam angles";
        end
        if ~isSpecular
            status.Text=string(p.factoryId)+" | "+status.Text;
            status.Tooltip=status.Text+" | "+factoryInfo.Text;
        end
        syncFactoryView();
        showFrame(1);
    end

    function toggleWaveforms(~,~)
        waveMode = ~waveMode;
        syncFactoryView();
        refreshFrame();
    end

    function syncFactoryView()
        canShow = ~isempty(data) && strcmp(data.configDirectory,configDir);
        if canShow && isSpecular
            canShow=strcmp(data.parameters.scenario,scenarioMenu.Value);
        elseif canShow
            canShow=strcmp(data.parameters.factoryId,scenarioMenu.Value) && strcmp(data.parameters.linkMode,linkMenu.Value);
        end
        viewButton.Enable = matlab.lang.OnOffSwitchState(canShow);
        if canShow && waveMode
            if isempty(factoryPanel)
                factoryPanel = uipanel(root,'BorderType','none','Tag','FactoryWaveformPanel');
                factoryPanel.Layout.Row = [2 3];
                factoryPanel.Layout.Column = [2 3];
                renderWaveforms = inf_waveform_view(factoryPanel,@renderScene,@(q) inf_channel_run(q,configDir,quadrigaDir));
            end
            factoryPanel.Visible = 'on';
            set(originalViews,'Visible','off');
            viewButton.Text = 'Geometry and channel plots';
        else
            if ~isempty(factoryPanel)
                factoryPanel.Visible = 'off';
            end
            set(originalViews,'Visible','on');
            viewButton.Text = 'Waveform recovery';
        end
    end

    function p = readSettings()
        v = radio.Data(:,2);
        p.bs = parse(v{1},3,'BS Position');
        p.ueStart = parse(v{2},3,'UE Start');
        p.ueEnd = parse(v{3},3,'UE End');
        p.fcGHz = bounded(v{4},0.5,100,'Carrier');
        p.bwMHz = bounded(v{5},1,1000,'Bandwidth');
        p.tones = integer(v{6},16,1024,'Tones');
        antennas = parse(v{7},2,'Antennas');
        p.nTx = integer(antennas(1),1,32,'BS Antennas');
        p.nRx = integer(antennas(2),2,16,'UE Antennas');
        p.txDbm = bounded(v{8},-30,60,'Transmit power');
        p.noiseFigure = bounded(v{9},0,30,'Noise figure');
        p.beam = parse(v{10},2,'Beam angle');
        if any(abs(p.beam)>90)
            error('BS Beam angles must lie within −90° to 90° within bounds.');
        end
        p.duration = bounded(v{11},0.1,120,'Duration');
        p.frames = integer(v{12},2,301,'Frames');
        p.seed = integer(v{13},0,2^32-1,'Random seed');
        p.aoaToleranceDeg = bounded(v{14},0.25,45,'AoA error warning tolerance');
        p.scenario = scenarioMenu.Value;
        if ~isSpecular
            p.factoryId=scenarioMenu.Value;
            p.linkMode=linkMenu.Value;
        end
        p.scanMode = scanMenu.Value;
        p.txElementRollDeg = txRoll.Value;
        p.useBox = useBox.Value;
        v = boxSettings.Data(:,2);
        p.boxCenter = parse(v{1},3,'Box center');
        p.boxSize = parse(v{2},3,'Box size');
        p.boxLoss = bounded(v{3},0,100,'Box loss');
        if isSpecular
            r=reflectionSettings.Data(:,2);
            p.wallOffset=bounded(r{1},.01,100,'Wall offset');
            p.reflectionMagnitude=bounded(r{2},0,1,'Reflection magnitude');
            p.directLossDb=bounded(r{3},0,80,'LOS extra loss');
            p.scanMode='manual';
        end
        if any(p.boxSize<=0)
            error('Box length, width, height must be positive.');
        end
    end

    function refreshClusterDisplay(~,~)
        refreshFrame();
    end

    function refreshFrame(~,~)
        if ~isempty(data)
            showFrame(frame);
        end
    end

    function showFrame(index)
        frame = index;
        now = data.time(frame);
        readout.Text = sprintf('Time %.2f s · %d / %d frames',now,frame,numel(data.time));
        shownCluster = data.strongestNlos(frame);
        nlosLabel = 'Strongest NLOS cluster';
        nlosPower = nan(size(data.time));
        if size(data.pathDbm,1)>1
            nlosPower = max(data.pathDbm(2:end,:),[],1);
        end
        nlosAngles = data.anglesDeg(3,:);
        if clusterMenu.Value~=0
            shownCluster = clusterMenu.Value;
            nlosLabel = sprintf('NLOS cluster #%d',shownCluster);
            nlosPower = data.pathDbm(shownCluster,:);
            nlosAngles = data.nlosClusterAnglesDeg(shownCluster,:);
        end
        if ~isempty(factoryPanel) && strcmp(factoryPanel.Visible,'on')
            renderWaveforms(data,frame,shownCluster,generation,clusterMenu.Value);
            return
        end
        if sceneTabs.SelectedTab==ancestor(sceneAx,'uitab')
            renderScene(sceneAx,shownCluster,false);
        else
            renderScene(topAx,shownCluster,true);
        end
        if powerTabs.SelectedTab==ancestor(powerAx,'uitab')
            renderPowerCurve(now,shownCluster,nlosLabel,nlosPower);
        else
            renderClusterPower(now,shownCluster);
        end
        if delayTabs.SelectedTab==ancestor(waterfallAx,'uitab')
            renderDelayHistory(now);
        elseif delayTabs.SelectedTab==ancestor(cleanAx,'uitab')
            renderDelay(cleanAx,now,true);
        else
            renderDelay(delayAx,now,false);
        end
        if results.SelectedTab==ancestor(rangeAx,'uitab')
            renderRange(now);
        elseif results.SelectedTab==ancestor(channelAx,'uitab')
            renderChannel(now);
        elseif results.SelectedTab==ancestor(angleCheckAx,'uitab')
            renderAngleCheck(now);
        else
            renderAngle(now,nlosLabel,nlosAngles);
        end
    end

    function renderPowerCurve(now,shownCluster,nlosLabel,nlosPower)
        delete(allchild(powerAx));
        plot(powerAx,data.time,data.pathDbm(1,:),'Color',teal,'LineWidth',1.7,'DisplayName','Direct path');
        hold(powerAx,'on');
        plot(powerAx,data.time,nlosPower,'Color',orange,'LineWidth',1.7,'DisplayName',nlosLabel);
        plot(powerAx,data.time,data.totalNlosDbm,'--','Color',[0.52 0.35 0.14], ...
            'LineWidth',1.3,'DisplayName','Total NLOS power');
        if isfinite(shownCluster)
            plot(powerAx,now,nlosPower(frame),'o','MarkerFaceColor',orange, ...
                'Color',orange,'HandleVisibility','off');
        end
        if data.isLos
            plot(powerAx,now,data.pathDbm(1,frame),'o','MarkerFaceColor',teal, ...
                'Color',teal,'HandleVisibility','off');
        end
        hold(powerAx,'off');
        timeAxis(powerAx,now,'Mean power per antenna (dBm)');
        if data.isLos
            title(powerAx,sprintf('LOS %.1f  |  NLOS #%d %.1f dBm', ...
                data.pathDbm(1,frame),shownCluster,nlosPower(frame)));

        else
            title(powerAx,'No valid direct component in this configuration');
        end
        lg = legend(powerAx,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
    end

    function renderClusterPower(now,shownCluster)
        delete(allchild(clusterAx));
        power = data.pathDbm(:,frame);
        scatter(clusterAx,2:numel(power),power(2:end),24,[0.45 0.49 0.55],'filled', ...
            'DisplayName','NLOS cluster');
        hold(clusterAx,'on');
        if data.isLos
            scatter(clusterAx,1,power(1),48,teal,'filled','DisplayName','LOS');
        end
        if isfinite(shownCluster)
            scatter(clusterAx,shownCluster,power(shownCluster),48,orange,'filled', ...
                'DisplayName',sprintf('Viewing #%d',shownCluster));
        end
        hold(clusterAx,'off');
        xlim(clusterAx,[0.5 numel(power)+0.5]);
        xlabel(clusterAx,'Channel cluster index'); ylabel(clusterAx,'Mean power per antenna (dBm)');
        title(clusterAx,sprintf('t = %.2f s | Per-cluster power',now));
        pos_plot_style(clusterAx);
        lg = legend(clusterAx,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
    end

    function renderDelay(ax,now,clean)
        delete(allchild(ax));
        profile = data.toaProfileDbm(:,:,frame);
        delaysNs = data.delayGridS*1e9;
        refNs = data.referenceDelayS(frame)*1e9;
        diag = data.toaDiagnostic;
        peakNs = diag.peakDelayS(:,frame)*1e9;
        note = sprintf('%s  |  %+.2f ns / %+.2f m',diag.reason(frame), ...
            diag.errorS(frame)*1e9,data.rangeM(frame)-data.trueDistanceM(frame));
        if ~data.isLos
            note = char(diag.reason(frame));
        end
        losLabel = 'Only LOS';
        if clean
            losLabel = 'Only LOS □';
        end
        plot(ax,delaysNs,profile(1,:),'Color',teal,'LineWidth',1.5,'DisplayName',losLabel);
        hold(ax,'on');
        if clean
            plot(ax,delaysNs,data.cleanToaProfileDbm(:,frame),'--','Color',orange, ...
                'LineWidth',1.5,'DisplayName','Noise-free profile');
            plot(ax,delaysNs,profile(3,:),'Color',purple,'LineWidth',1.1, ...
                'DisplayName','Received total profile ○');
            stageProfiles = [profile(1,:);data.cleanToaProfileDbm(:,frame).';profile(3,:)];
            markerStyles = {'s','d','o'};
            markerColors = [teal;orange;purple];
            markerSizes = [10 8 5];
            for stage = 1:3
                k = diag.peakIndex(stage,frame);
                if isfinite(k)
                    plot(ax,peakNs(stage),stageProfiles(stage,k),markerStyles{stage}, ...
                        'Color',markerColors(stage,:),'MarkerSize',markerSizes(stage), ...
                        'LineWidth',1.6,'HandleVisibility','off');
                end
            end
            heading = sprintf('%.2f s | LOS %.2f / Noise-free %.2f / Received %.2f ns',now,peakNs);
        else
            plot(ax,delaysNs,profile(2,:),'--','Color',orange,'LineWidth',1.5, ...
                'DisplayName','NLOS coherent sum');
            plot(ax,delaysNs,profile(3,:),'Color',purple,'LineWidth',1.5,'DisplayName','Received profile');
            k = diag.peakIndex(3,frame);
            plot(ax,peakNs(3),profile(3,k),'o','Color',purple,'MarkerFaceColor',purple, ...
                'HandleVisibility','off');
            heading = sprintf('t = %.2f s | Received peak %.2f ns (%.2f m)',now,peakNs(3),data.rangeM(frame));
        end
        xline(ax,refNs,':k',sprintf('Geometry %.2f ns',refNs), ...
            'LabelVerticalAlignment','bottom','HandleVisibility','off');
        hold(ax,'off');
        lg = legend(ax,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
        xlabel(ax,'Absolute propagation delay (ns)'); ylabel(ax,'Response power (dBm)');
        xlim(ax,delaysNs([1 end]));
        upper = max(data.toaProfileDbm,[],'all','omitnan');
        ylim(ax,[upper-65 upper+4]);
        title(ax,{heading,note},'FontSize',13);
        pos_plot_style(ax);
    end

    function renderAngleCheck(now)
        ax = angleCheckAx;
        delete(allchild(ax));
        diag = data.aoaDiagnostic;
        plot(ax,data.time,data.anglesDeg(2,:),'k:','LineWidth',1.25,'DisplayName','Geometry LOS');
        hold(ax,'on');
        plot(ax,data.time,diag.losOnlyDeg,'--','Color',teal,'LineWidth',1.4,'DisplayName','Only LOS');
        plot(ax,data.time,diag.nlosOnlyDeg,':','Color',orange,'LineWidth',1.3,'DisplayName','Only NLOS');
        plot(ax,data.time,diag.cleanDeg,'--','Color',[0.33 0.38 0.65], ...
            'LineWidth',1.4,'DisplayName','Noise-free full channel');
        plot(ax,data.time,data.anglesDeg(1,:),'Color',purple,'LineWidth',1.7,'DisplayName','Received estimate');
        hold(ax,'off');
        lg = legend(ax,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
        timeAxis(ax,now,'ULA projected angle (°)');
        heading = sprintf('%.2f s | LOS %.1f° / Clean %.1f° / Received %.1f°', ...
            now,diag.losOnlyDeg(frame),diag.cleanDeg(frame),data.anglesDeg(1,frame));
        title(ax,{heading,char(diag.reason(frame))},'FontSize',13);
    end

    function renderDelayHistory(now)
        if isempty(historyCursor) || ~isvalid(historyCursor)
            power = reshape(data.toaProfileDbm(3,:,:),numel(data.delayGridS),[]);
            imagesc(waterfallAx,data.time,data.delayGridS*1e9,power);
            waterfallAx.YDir = 'normal';
            peak = max(power,[],'all');
            clim(waterfallAx,[peak-55 peak]);
            scale = colorbar(waterfallAx);
            scale.Label.String = 'Response power (dBm)';
            hold(waterfallAx,'on');
            plot(waterfallAx,data.time,data.referenceDelayS*1e9,'w--','LineWidth',1.1, ...
                'DisplayName','Geometric direct delay');
            plot(waterfallAx,data.time,data.toaPeakDelayS*1e9,'.','Color',[1 0.72 0.34], ...
                'DisplayName','Strongest received peak');
            late = data.toaDiagnostic.lateReflection;
            if any(late)
                plot(waterfallAx,data.time(late),data.toaPeakDelayS(late)*1e9,'ro', ...
                    'MarkerSize',4,'DisplayName','Late reflection');
            end
            historyCursor = xline(waterfallAx,now,'w-','HandleVisibility','off');
            hold(waterfallAx,'off');
            xlim(waterfallAx,data.time([1 end]));
            ylim(waterfallAx,data.delayGridS([1 end])*1e9);
            xlabel(waterfallAx,'Time (s)'); ylabel(waterfallAx,'Absolute propagation delay (ns)');
            lg = legend(waterfallAx,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
        end
        historyCursor.Value = now;
        title(waterfallAx,{sprintf('t = %.2f s | Received profile over time',now), ...
            char(data.toaDiagnostic.reason(frame))},'FontSize',13);
    end

    function renderAngle(now,nlosLabel,nlosAngles)
        delete(allchild(angleAx));
        plot(angleAx,data.time,data.centerToneAnglesDeg,':','Color',[0.46 0.48 0.52], ...
            'LineWidth',1.3,'DisplayName','Center tone');
        hold(angleAx,'on');
        plot(angleAx,data.time,data.anglesDeg(1,:),'Color',purple,'LineWidth',1.8, ...
            'DisplayName','Principal direction');
        plot(angleAx,data.time,data.anglesDeg(2,:),'--','Color',teal,'LineWidth',1.5, ...
            'DisplayName','Geometry LOS');
        plot(angleAx,data.time,nlosAngles,'Color',orange,'LineWidth',1.25, ...
            'DisplayName',[nlosLabel 'Reference']);
        diag = data.aoaDiagnostic;
        if any(diag.miss)
            plot(angleAx,data.time(diag.miss),data.anglesDeg(1,diag.miss),'o', ...
                'Color',red,'MarkerSize',4, ...
                'DisplayName',sprintf('deviation from LOS > %.1f°',diag.toleranceDeg));
        end
        plot(angleAx,now,data.anglesDeg(1,frame),'o','Color',purple, ...
            'MarkerFaceColor',purple,'HandleVisibility','off');
        hold(angleAx,'off');
        lg = legend(angleAx,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
        timeAxis(angleAx,now,'ULA projected angle (°)');
        heading = sprintf('t = %.2f s | Estimate %.1f° / Geometry LOS %.1f°', ...
            now,data.anglesDeg(1,frame),data.anglesDeg(2,frame));
        note = char(diag.reason(frame));
        if data.isLos
            note = sprintf('%s  |  %+.1f°',note,diag.errorDeg(frame));
        end
        title(angleAx,{heading,note},'FontSize',13);
    end

    function renderRange(now)
        delete(allchild(rangeAx));
        plot(rangeAx,data.time,[data.rangeM;data.trueDistanceM].','LineWidth',1.6);
        colororder(rangeAx,[purple;teal]);
        labels = {'Strongest peak ToA','Geometric distance'};
        late = data.toaDiagnostic.lateReflection;
        if any(late)
            hold(rangeAx,'on');
            plot(rangeAx,data.time(late),data.rangeM(late),'o','Color',red,'MarkerSize',4);
            hold(rangeAx,'off');
            labels{end+1} = 'Late reflection selected';
        end
        lg = legend(rangeAx,labels,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
        timeAxis(rangeAx,now,'Range (m)');
        title(rangeAx,{sprintf('t = %.2f s | Range error %+.2f m',now,data.rangeM(frame)-data.trueDistanceM(frame)), ...
            char(data.toaDiagnostic.reason(frame))},'FontSize',13);
    end

    function renderChannel(now)
        imagesc(channelAx,data.frequencyOffsetsHz/1e6,1:data.parameters.nRx, ...
            20*log10(max(abs(data.Y(:,:,frame)),realmin)));
        channelAx.YDir = 'normal';
        ylim(channelAx,[0.5 data.parameters.nRx+0.5]);
        xlabel(channelAx,'Frequency offset (MHz)'); ylabel(channelAx,'UE element');
        channelColor = colorbar(channelAx);
        channelColor.Label.String = 'Power per tone (dBm)';
        title(channelAx,sprintf('t = %.2f s | Received pilot matrix Y',now));
    end

    function renderScene(ax,cluster,topView)
        delete(allchild(ax));
        hold(ax,'on');
        ue = data.ue(:,frame);
        paintLine(ax,data.ue,[0.5 0.56 0.64],':',2,'UE Track');
        endpoints = data.ue(:,[1 end]);
        plot3(ax,endpoints(1,:),endpoints(2,:),endpoints(3,:),'.', ...
            'Color',[0.5 0.56 0.64],'MarkerSize',12,'HandleVisibility','off');
        if data.isLos
            style = '-';
            label = 'LOS';
            if data.blocked(frame)
                style = '--';
                label = 'LOS · Box attenuation';
            end
            paintLine(ax,[data.bs ue],teal,style,2,label);
        end
        firstBounce=data.fbs; lastBounce=data.lbs;
        if isfield(data,'fbsTrack')
            firstBounce=data.fbsTrack(:,:,frame); lastBounce=data.lbsTrack(:,:,frame);
        end
        if isfinite(cluster)
            paintLine(ax,[data.bs firstBounce(:,cluster) lastBounce(:,cluster) ue], ...
                orange,'--',1.5,sprintf('NLOS #%d (schematic)',cluster));
        end
        if data.parameters.useBox
            drawBox(ax,data.parameters.boxCenter(:),data.parameters.boxSize(:));
        end
        plot3(ax,data.bs(1),data.bs(2),data.bs(3),'ks','MarkerFaceColor','k','DisplayName','BS');
        plot3(ax,ue(1),ue(2),ue(3),'ko','MarkerFaceColor',teal,'DisplayName','Current UE');
        heading = data.beamHeadingDeg(frame);
        arrow = max(1,norm(data.bs-ue)*0.15);
        quiver3(ax,data.bs(1),data.bs(2),data.bs(3),arrow*cosd(heading), ...
            arrow*sind(heading),0,0,'Color',purple,'LineWidth',2,'DisplayName','BS Beam');
        hold(ax,'off');
        pos_plot_style(ax);
        if topView
            view(ax,2);
        else
            view(ax,[-32 26]);
            zlabel(ax,'z (m)');
        end
        if topView
            axis(ax,'equal');
        else
            axis(ax,'normal');
            pbaspect(ax,[1.6 1 0.8]);
        end
        xlabel(ax,'x (m)'); ylabel(ax,'y (m)');
        title(ax,sprintf('t = %.2f s | BS Scan angle %.1f°',data.time(frame),heading));
        lg = legend(ax,'Location','northoutside','Orientation','horizontal','NumColumns',2,'FontSize',11);
        if ~isempty(lg.Layout)
            lg.Layout.Tile = 'north';
        else
            lg.Location = 'best';
            lg.NumColumns = 1;
        end
    end

    function paintLine(ax,points,color,style,width,label)
        plot3(ax,points(1,:),points(2,:),points(3,:),style, ...
            'Color',color,'LineWidth',width,'DisplayName',label);
    end

    function drawBox(ax,center,dims)
        signs = [-1 -1 -1;1 -1 -1;1 1 -1;-1 1 -1;-1 -1 1;1 -1 1;1 1 1;-1 1 1];
        vertices = center.'+signs.*(dims.'/2);
        faces = [1 2 3 4;5 6 7 8;1 2 6 5;2 3 7 6;3 4 8 7;4 1 5 8];
        patch(ax,'Vertices',vertices,'Faces',faces,'FaceColor',[0.5 0.4 0.55], ...
            'FaceAlpha',0.35,'DisplayName','Attenuation box');
    end

    function timeAxis(ax,now,label)
        xline(ax,now,':k','HandleVisibility','off');
        xlim(ax,data.time([1 end]));
        xlabel(ax,'Time (s)'); ylabel(ax,label);
        pos_plot_style(ax);
    end

    function seek(value)
        pausePlayback();
        if ~isempty(data)
            showFrame(round(value));
        end
    end

    function startPlayback(~,~)
        if frame==numel(data.time)
            slider.Value = 1;
            showFrame(1);
        end
        play.Enable = 'off';
        pauseButton.Enable = 'on';
        start(clock);
    end

    function advance(~,~)
        slider.Value = frame+1;
        showFrame(frame+1);
        if frame==numel(data.time)
            stop(clock);
        end
    end

    function pausePlayback(~,~)
        if strcmp(clock.Running,'on')
            stop(clock);
        end
    end

    function playbackStopped(~,~)
        if isvalid(fig) && strcmp(fig.BeingDeleted,'off')
            play.Enable = 'on';
            pauseButton.Enable = 'off';
        end
    end

    function saveData(~,~)
        pausePlayback();
        [file,folder] = uiputfile('*.mat','Export multipath, array and localization data','inf_localization_run.mat');
        if ischar(file)
            data.selectedFrame = frame;
            save(fullfile(folder,file),'-struct','data','-v7.3');
        end
    end

    function savePower(~,~)
        pausePlayback();
        [file,folder] = uiputfile('*.png','Export LOS and strongest NLOS Power plot','inf_power_over_time.png');
        if ischar(file)
            inf_power_plot(data,fullfile(folder,file));
        end
    end
end

function tabs = tabPanel(layout,row,column,callback)
tabs = uitabgroup(layout,'SelectionChangedFcn',callback);
tabs.Layout.Row = row;
tabs.Layout.Column = column;
end

function ax = tabAxes(tabs,name,tag)
tab = uitab(tabs,'Title',name);
layout = tiledlayout(tab,1,1,'TileSpacing','compact','Padding','compact');
ax = nexttile(layout);
ax.Tag = tag;
pos_plot_style(ax);
end

function value = parse(input,count,label)
if isnumeric(input)
    value = input;
else
    value = str2double(split(strtrim(string(input)),regexpPattern('[\s,, ]+'))).';
end
if numel(value)~=count || any(~isfinite(value)) || ~isreal(value)
    error('%s must contain %d finite numbers.',label,count);
end
end

function value = bounded(input,lower,upper,label)
value = parse(input,1,label);
if value<lower || value>upper
    error('%s must lie between %g to %g within bounds.',label,lower,upper);
end
end

function value = integer(input,lower,upper,label)
value = bounded(input,lower,upper,label);
if value~=floor(value)
    error('%s must be an integer.',label);
end
end
