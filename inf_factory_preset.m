function f = inf_factory_preset(id)
% TR 38.901 Tables 7.2-4 and 7.8-7. HH uses illustrative high antennas.
% 1.5/8 m are calibration defaults. Link validation checks height vs clutter.
id = validatestring(id,{'InF-SL','InF-SH','InF-DL','InF-DH','InF-HH'});
f = struct('id',id,'hallM',[120 60 10],'density',0.2,'sizeM',10, ...
    'clutterHeightM',2,'bsHeightM',1.5,'utHeightM',1.5);
if ismember(string(id),["InF-SH","InF-DL"]), f.hallM=[300 150 10]; end
if startsWith(id,'InF-D')
    f.density=.6; f.sizeM=2; f.clutterHeightM=6;
end
if endsWith(id,'H'), f.bsHeightM=8; end
if strcmp(id,'InF-HH'), f.utHeightM=7; end
end
