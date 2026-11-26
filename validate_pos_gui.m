function validate_pos_gui(uiOnly)
% Validate physical geometry, consistent observations, and real GUI callbacks.
root=fileparts(mfilename('fullpath')); addpath(root,'-begin');
if nargin<1, uiOnly=false; end
report=fullfile(root,'validation'); if ~isfolder(report), mkdir(report); end
p=struct('bs',[0 0 1.5],'ueStart',[16 -.12 1.5],'ueEnd',[16 .12 1.5], ...
    'fcGHz',5.2,'bwMHz',80,'tones',65,'nTx',4,'nRx',4,'txDbm',20, ...
    'noiseFigure',7,'beam',[0 0],'duration',2,'frames',3,'seed',723, ...
    'aoaToleranceDeg',5,'scanMode','manual','useBox',false, ...
    'boxCenter',[8 0 4],'boxSize',[1 1.5 5],'boxLoss',20, ...
    'txElementRollDeg',0,'wallOffset',2,'reflectionMagnitude',.8,'directLossDb',0);
quad='D:/biye/code_f/env2024-main (1)/env2024-main/quadriga_src';
if ~uiOnly
for walls=1:3
    p.scenario=['Specular_' num2str(walls)];
    d=inf_channel_run(p,fullfile(root,'config'),'not-required');
    assert(size(d.pathDbm,1)==walls+1);
    assert(all(d.referenceDelayS>0) && all(isfinite(d.Y),'all'));
    direct=reshape(d.delayS(1,1,1,:),1,[]);
    assert(max(abs(direct-d.referenceDelayS))<1e-15);
    assert(all(d.delayS(:,:,2:end,:)>=d.delayS(:,:,1,:),'all'));
    for k=1:p.frames
        fromPorts=reshape(sum(double(d.mimoPilot(:,:,:,k)).*reshape(d.beamWeights(:,k),1,[],1),2),p.nRx,p.tones);
        assert(norm(fromPorts-d.Y(:,:,k),'fro')<1e-6*norm(d.Y(:,:,k),'fro'));
    end
    fprintf('PASS Specular_%d geometry and pilot consistency\n',walls);
end
if isfolder(quad)
    p.tones=513; % Cover the delayed clusters in the stochastic InF profiles.
    for profile=["LOS","NLOS_SL","NLOS_DL","NLOS_SH","NLOS_DH"]
        p.scenario=char("3GPP_38.901_InF_"+profile); p.addPhysicalLos=false;
        d=inf_channel_run(p,fullfile(root,'config'),quad);
        assert(d.isLos==(profile=="LOS")); assert(~d.addedLos);
        assert(all(isfinite(d.Y),'all'));
        fprintf('PASS native %s\n',profile);
        if profile~="LOS"
            p.addPhysicalLos=true; a=inf_channel_run(p,fullfile(root,'config'),quad);
            assert(a.addedLos && a.isLos && all(sum(abs(a.losPilotFirstRx).^2,1)>0));
            fprintf('PASS added-LOS %s\n',profile);
        end
    end
end
end
f=pos_gui(quad); finish=onCleanup(@() close(f)); drawnow; pause(2);
exportapp(f,fullfile(report,'stage_01.png'));
t=findobj(f,'Tag','ExperimentStages');
for index=2:3
    if index==2, tag='StageReflections'; else, tag='Stage3GPP'; end
    stage=findobj(f,'Tag',tag); t.SelectedTab=stage;
    t.SelectionChangedFcn(t,[]); drawnow;
    radios=findobj(stage,'Tag','RadioParameters'); radios.Data{6,2}='65'; radios.Data{12,2}='3';
    radios.Data{7,2}='4 4';
    if index==3, radios.Data{4,2}='5.2'; radios.Data{5,2}='80'; radios.Data{6,2}='513'; end
    run=findobj(stage,'Tag','GenerateChannel'); run.ButtonPushedFcn(run,[]); drawnow;
    assert(isstruct(f.UserData) && isfield(f.UserData,'Y'));
    drawnow; pause(2); exportapp(f,fullfile(report,sprintf('stage_%02d.png',index))); pause(2);
    view=findobj(stage,'Tag','FactoryWaveformToggle'); assert(strcmp(view.Enable,'on'));
    view.ButtonPushedFcn(view,[]); drawnow;
    assert(numel(findobj(stage,'-regexp','Tag','^FactoryWaveform[1-9]$'))==9);
    drawnow; pause(2); exportapp(f,fullfile(report,sprintf('stage_%02d_waveforms.png',index))); pause(2);
    for method={'spring','m3','radio'}
        menu=findobj(stage,'Tag','LosSeparationAlgorithm'); menu.Value=method{1};
        menu.ValueChangedFcn(menu,[]); drawnow;
    end
    fprintf('PASS stage %d UI and all four estimators\n',index);
end
fprintf('ALL CHECKS PASSED\n');
end
