function validate_observation_view()
% Numerical and GUI integration checks for observation contribution.
root=fileparts(mfilename('fullpath'));
report=fullfile(root,'validation');
if ~isfolder(report), mkdir(report); end
p=struct('bs',[0 0 1.5],'ueStart',[16 -.12 1.5],'ueEnd',[16 .12 1.5], ...
    'fcGHz',5.2,'bwMHz',80,'tones',65,'nTx',4,'nRx',4,'txDbm',20, ...
    'noiseFigure',7,'beam',[0 0],'duration',2,'frames',5,'seed',723, ...
    'aoaToleranceDeg',5,'scanMode','manual','useBox',false, ...
    'boxCenter',[8 0 4],'boxSize',[1 1.5 5],'boxLoss',20, ...
    'txElementRollDeg',0,'wallOffset',2,'reflectionMagnitude',.8,'directLossDb',0,'scenario','Specular_2');
d=inf_channel_run(p,fullfile(root,'config'),'unused');
r=inf_observation_projection(d,3,[0 0;.2 1;-100 0;0 100]);
assert(norm(r.xy(1,:)-d.ue(1:2,3).')<1e-10);
assert(isequal(r.valid,[true;true;false;false]));
v=nan(p.frames,3);
for k=1:p.frames
    [~,t,a]=inf_waveform_fit(d.Y(:,:,k),d.frequencyOffsetsHz,d.noisePerToneStd);
    if ~isempty(t),v(k,:)=[0 a(1) t(1)*1e9];end
end
f=inf_observation_view(d,v,'omp',3); finish=onCleanup(@() delete(f));drawnow;pause(2);
assert(f.UserData.totalCount==5);
assert(size(f.UserData.errors,2)==2);
scope=findobj(f,'Tag','ObservationScope');scope.Value='LOS-window matches only';scope.ValueChangedFcn(scope,[]);
scope.Value='All finite selections';scope.ValueChangedFcn(scope,[]);
source=findobj(f,'Tag','ObservationSource');source.Value='Fixed-channel noise trials';source.ValueChangedFcn(source,[]);
assert(contains(findobj(f,'Tag','ObservationSummary').Text,'Run noise trials'));
trial=findobj(f,'Type','uinumericeditfield');
trial(arrayfun(@(x) x.Limits(2)==300,trial)).Value=3;
button=findobj(f,'Tag','RunObservationTrials');button.ButtonPushedFcn(button,[]);
assert(f.UserData.totalCount==3);
assert(strcmp(f.UserData.source,'Frozen-channel noise trials'));
source.Value='Track residuals';source.ValueChangedFcn(source,[]);drawnow;pause(2);
exportapp(f,fullfile(root,'validation','observation_contribution.png'));pause(2);
spring=inf_observation_view(d,v,'spring',3);springCleanup=onCleanup(@() delete(spring));
nums=findobj(spring,'Type','uinumericeditfield');nums(arrayfun(@(x) x.Limits(2)==300,nums)).Value=3;
sb=findobj(spring,'Tag','RunObservationTrials');sb.ButtonPushedFcn(sb,[]);
assert(spring.UserData.totalCount==3);
clear springCleanup;
host=uifigure('Visible','off');cleanup=onCleanup(@() delete(host));
render=inf_waveform_view(host,@(a,varargin) plot(a,[0 1],[0 1]),@(q) d);
render(d,1,2,1,0);
b=findobj(host,'Tag','OpenObservationContribution');assert(strcmp(b.Enable,'on'));
b.ButtonPushedFcn(b,[]);drawnow;
windows=findall(groot,'Type','figure');
for w=windows.'
    if w~=f&&w~=host,delete(w);end
end
fprintf('PASS numerical projection, invalid geometry, scope, noise trials, CSV data fields and waveform-page integration\n');
fprintf('ALL OBSERVATION CHECKS PASSED\n');
end
