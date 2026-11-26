function fig = pos_gui(quadrigaDir)
%POS_GUI Three progressive experiments with the original scientific plots.
% Start here. Each stage is initialized once; switching tabs preserves data.
if nargin<1, quadrigaDir='D:/biye/code_f/env2024-main (1)/env2024-main/quadriga_src'; end
folder=fileparts(mfilename('fullpath'));
fig=uifigure('Name','LOS Experiment Studio','Position',[35 40 1530 920]);
grid=uigridlayout(fig,[3 1]); grid.RowHeight={38,28,'1x'};
uilabel(grid,'Text','LOS Experiment Studio | Separation to localization', ...
    'FontSize',23,'FontWeight','bold');
uilabel(grid,'Text','01 Identifiability  >  02 Detection / selection / waveform recovery  >  03 Complex-channel validation', ...
    'FontColor',[.3 .38 .45]);
tabs=uitabgroup(grid,'SelectionChangedFcn',@selectStage,'Tag','ExperimentStages');
one=uitab(tabs,'Title','01 | Two-path baseline','Tag','StageTwoPath');
two=uitab(tabs,'Title','02 | Specular reflections','Tag','StageReflections');
three=uitab(tabs,'Title','03 | 3GPP InF channels','Tag','Stage3GPP');
initialized=false(1,3);
fig.CloseRequestFcn=@closeStudio;
selectStage();
    function selectStage(~,~)
        % Pause hidden stages so background playback cannot consume resources.
        timers=getappdata(fig,'PosGuiTimers');
        for t=timers
            if isvalid(t) && strcmp(t.Running,'on'), stop(t); end
        end
        idx=find([one two three]==tabs.SelectedTab);
        if initialized(idx), return, end
        switch idx
            case 1, two_path_separation_gui(one);
            case 2, inf_localization_gui(fullfile(folder,'config'),quadrigaDir,two,'specular');
            case 3, inf_localization_gui(fullfile(folder,'config'),quadrigaDir,three,'3gpp');
        end
        initialized(idx)=true;
    end
    function closeStudio(~,~)
        timers=getappdata(fig,'PosGuiTimers');
        for t=timers
            if isvalid(t), stop(t); delete(t); end
        end
        delete(fig);
    end
end
