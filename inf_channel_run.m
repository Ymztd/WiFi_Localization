function data = inf_channel_run(p,configDir,quadrigaDir)
%INF_CHANNEL_RUN Generate one BS–UE track and evaluate its beamformed channel.
if isfield(p,'factoryId')
    p=inf_factory_link(p);
    if ~isfile(fullfile(configDir,[p.scenario '.conf']))
        error('inf:Profile','Missing %s.conf in the selected configuration folder.',p.scenario);
    end
end
isSpecular = startsWith(string(p.scenario),"Specular_");
previousDir=pwd; previousRng=rng;
restoreEnvironment=onCleanup(@() restore(previousDir,previousRng));
if ~isSpecular
    if ~isfolder(fullfile(quadrigaDir,'@qd_layout'))
        error('Select a valid QuaDRiGa quadriga_src folder.');
    end
    if ~isfolder(configDir), error('Configuration folder not found.'); end
    addpath(quadrigaDir,'-begin');
    cd(configDir);
end
rng(p.seed,'twister');

c = 299792458;
fc = p.fcGHz*1e9;
bw = p.bwMHz*1e6;
time = linspace(0,p.duration,p.frames);
fraction = time/p.duration;
ue = p.ueStart(:)+(p.ueEnd(:)-p.ueStart(:))*fraction;
bs = p.bs(:);
if any(vecnorm(ue-bs)<0.1) || min(ue(3,:))<=0 || bs(3)<=0
    error('Antenna heights must be positive, and in each snapshot BS and UE minimum separation 0.1 m.');
end
arraySpacing = 0.45*c/fc;
isStatic=all(p.ueStart==p.ueEnd);
if isSpecular
    [raw,delays,fbsTrack,lbsTrack,ue,bs]=specular_channel_setup(p);
    fbs=fbsTrack(:,:,1); lbs=lbsTrack(:,:,1);
    scenario=string(p.scenario); nativeLos=true; addedLos=false; isLos=true;
    numClusters=size(raw,3);
else
arraySpacing = 0.45*c/fc;
sim = qd_simulation_parameters;
sim.center_frequency = fc;
sim.use_absolute_delays = true;
sim.use_3GPP_baseline = false;
sim.show_progress_bars = false;
layout = qd_layout(sim);
layout.tx_position = bs;
roll = 0;
if isfield(p,'txElementRollDeg'), roll=p.txElementRollDeg; end
validateattributes(roll,{'numeric'},{'scalar','real','finite','>=',-90,'<=',90});
layout.tx_array = makeArray(p.nTx,arraySpacing,roll);
layout.rx_array = makeArray(p.nRx,arraySpacing);
track = qd_track;
track.name = 'UEtrack';
track.initial_position = ue(:,1);
isStatic = all(p.ueStart==p.ueEnd);
if ~isStatic
    track.positions = ue-ue(:,1);
end
layout.rx_track = track;
layout.set_scenario(char(p.scenario),[],[],1,[],[],false);
builder = layout.init_builder;
if isfield(p,'factoryId')
    % The regular scenpar setter renames this native profile to Custom.
    sp=builder.scenpar;
    sp.DS_mu=p.factory.logDelaySpreadMean;
    builder.scenpar_nocheck=sp;
end
gen_parameters(builder);
channel = get_channels(builder);
scenario = string(builder.scenario);
nativeLos = contains(scenario,"_LOS");
addedLos = startsWith(scenario,"3GPP_38.901_InF_NLOS_");
% Preserve the historical added-LOS experiment unless explicitly disabled.
if isfield(p,'addPhysicalLos'), addedLos=addedLos && p.addPhysicalLos; end
isLos = nativeLos || addedLos;
raw = channel.coeff;
delays = channel.delay;
numClusters = channel.no_path;
if double(p.nRx)*p.nTx*p.tones*p.frames*numClusters > 2e8
    error('Path-frequency workload is too large, reduce antennas, tones or frames.');
end
numSubpaths = channel.par.NumSubPaths;
firstSubpath = 1+[0 cumsum(numSubpaths(1:end-1))];
fbs = double(channel.par.fbs_pos(:,firstSubpath));
lbs = double(channel.par.lbs_pos(:,firstSubpath));
end
frequencies = (-floor(p.tones/2):ceil(p.tones/2)-1)*(bw/p.tones);
center = floor(p.tones/2)+1;
maxDelay = max(max(delays(:)),max(vecnorm(ue-bs))/c);
unambiguousDelay = p.tones/bw;
if maxDelay>=unambiguousDelay
    error('A path exceeds the unambiguous delay interval, increase tones or reduce bandwidth.');
end
lastDelayBin = min(8*p.tones-1,ceil((maxDelay+8/bw)*bw*8));
delayGrid = (0:lastDelayBin)/(bw*8);
delayWindow = 0.5-0.5*cos(2*pi*(0:p.tones-1)/(p.tones-1));
inverse = delayWindow(:).*exp(2i*pi*frequencies(:)*delayGrid)/sum(delayWindow);
pilot = sqrt(10^(p.txDbm/10)/p.tones);
noiseStd = sqrt(10^((-174+10*log10(bw/p.tones)+p.noiseFigure)/10)/2);
repeats = 16;
txIndex = (0:p.nTx-1)'-(p.nTx-1)/2;
rxIndex = (0:p.nRx-1)'-(p.nRx-1)/2;
axisPhase = 2*pi*fc*arraySpacing/c;
scan = -90:0.25:90;
manifold = exp(1i*axisPhase*rxIndex*sind(scan));
heading = p.beam(1)+(p.beam(2)-p.beam(1))*fraction;
targetCluster = NaN;
scanMode = "manual";
if isfield(p,'scanMode')
    scanMode = string(p.scanMode);
end
if nativeLos && numClusters>1 && p.nTx>1 && scanMode~="manual"
    % Complete the one-way sweep before the end so the final beam is observable.
    transition = (1-cos(pi*min(fraction/0.75,1)))/2;
    if scanMode=="return"
        transition = (1-cos(2*pi*fraction))/2;
    end
    losHeading = asind((ue(2,:)-bs(2))./vecnorm(ue-bs));
    startW = exp(-1i*axisPhase*txIndex*sind(losHeading(1)))/sqrt(p.nTx);
    aimFrames = find(transition==max(transition));
    aimFrames = aimFrames(unique(round(linspace(1,numel(aimFrames),5))));
    if isStatic
        aimFrames = 1;
    end
    allW = exp(-1i*axisPhase*txIndex*sind(scan))/sqrt(p.nTx);
    searchTones = frequencies(unique(round(linspace(1,p.tones,min(17,p.tones)))));
    initialNlos = 0;
    sampledPower = zeros(numClusters,numel(scan),numel(aimFrames));
    for cluster = 1:numClusters
        if cluster>1
            initialNlos = max(initialNlos,beamPower( ...
                raw(:,:,cluster,1),delays(:,:,cluster,1),searchTones,startW));
        end
        for sample = 1:numel(aimFrames)
            k = aimFrames(sample);
            sampledPower(cluster,:,sample) = beamPower(raw(:,:,cluster,k), ...
                delays(:,:,cluster,k),searchTones,allW);
        end
    end
    [strongest,clusters] = max(sampledPower(2:end,:,:),[],1);
    % Evaluate the held beam at several UE positions, including the endpoint.
    meanStrongest = mean(strongest,3);
    dominanceDb = min(10*log10(strongest./sampledPower(1,:,:)),[],3);
    improvementDb = 10*log10(min(strongest,[],3)/initialNlos);
    eligible = dominanceDb>=8 & improvementDb>=3;
    if ~any(eligible)
        eligible = dominanceDb>=8 & improvementDb>0;
    end
    if ~any(eligible)
        eligible = dominanceDb>0 & improvementDb>0;
    end
    if ~any(eligible)
        eligible = dominanceDb>0;
    end
    candidates = meanStrongest;
    if any(eligible)
        candidates(~eligible) = -Inf;
    end
    [~,beamIndex] = max(candidates);
    targetCluster = clusters(1,beamIndex,end)+1;
    heading = losHeading+(scan(beamIndex)-losHeading).*transition;
end
weights = exp(-1i*axisPhase*txIndex*sind(heading))/sqrt(p.nTx);

H = complex(zeros(p.nRx,p.tones,p.frames));
Y = H;
losPilot = complex(zeros(p.tones,p.frames));
losArrayPilot = complex(zeros(p.nRx,p.tones,p.frames,'single'));
competitorArrayPilot = losArrayPilot;
competitorSlot = nan(1,p.frames);
competitorCoherence = nan(1,p.frames);
principal = complex(zeros(p.nRx,p.frames));
centerPrincipal = principal;
centerAngle = nan(1,p.frames);
pathDbm = nan(numClusters,p.frames);
angle = nan(3,p.frames);
range = nan(1,p.frames);
toaProfile = nan(3,numel(delayGrid),p.frames);
cleanToaProfile = nan(numel(delayGrid),p.frames);
peakDelay = nan(1,p.frames);
strongestNlos = nan(1,p.frames);
clusterAngles = nan(numClusters,p.frames);
blocked = false(1,p.frames);
referenceDistance = vecnorm(ue-bs);
referenceDelay = referenceDistance/c;
angle(2,:) = asind((bs(2)-ue(2,:))./referenceDistance);
addedLosPathLossDb = nan(1,p.frames);
directField = ones(1,p.frames);
if addedLos
    addedLosPathLossDb = indoorLosPathLoss(referenceDistance,p.fcGHz);
    if isfield(p,'txElementRollDeg')
        % Vertical RX couples to the transmitted vertical field in LOS.
        % Normalize both field patterns to the upright broadside reference.
        [az,el]=cart2sph(ue(1,:)-bs(1),ue(2,:)-bs(2),ue(3,:)-bs(3));
        ref=layout.rx_array.interpolate(0,0,1);
        txV=layout.tx_array.interpolate(az,el,1);
        rxV=layout.rx_array.interpolate(atan2(-sin(az),-cos(az)),-el,1);
        directField=txV.*rxV/ref^2;
    end
end
angleTolerance = 5;
if isfield(p,'aoaToleranceDeg')
    angleTolerance = p.aoaToleranceDeg;
end
toaDiagnostic = struct('peakDelayS',nan(3,p.frames),'stageShiftS',nan(3,p.frames), ...
    'peakIndex',nan(3,p.frames),'errorS',nan(1,p.frames),'lateReflection',false(1,p.frames), ...
    'reason',strings(1,p.frames),'gridStepS',1/(8*bw),'mainLobeHalfWidthS',2/bw);
aoaDiagnostic = struct('losOnlyDeg',nan(1,p.frames),'cleanDeg',nan(1,p.frames), ...
    'nlosOnlyDeg',nan(1,p.frames),'errorDeg',nan(1,p.frames), ...
    'miss',false(1,p.frames),'reason',strings(1,p.frames),'toleranceDeg',angleTolerance);
% Orthogonal port pilots on the same frozen channel. A separate RNG leaves
% the existing receiver observations and trajectory reproducible.
mimoPilot = complex(zeros(p.nRx,p.nTx,p.tones,p.frames,'single'));
probeRng = RandStream('mt19937ar','Seed',mod(double(p.seed)+1949,2^32));
for frame = 1:p.frames
    k = frame;
    if isStatic
        k = 1;
    end
    if isSpecular
        k=frame;
        fbs=fbsTrack(:,:,frame); lbs=lbsTrack(:,:,frame);
    end
    % A native NLOS configuration reserves slot 1 for the direct path.
    nlos = 2:numClusters;
    path = complex(zeros(p.nRx,p.tones,numClusters));
    ports = complex(zeros(p.nRx,p.nTx,p.tones));
    blocked(frame) = p.useBox && intersectsBox(bs,ue(:,frame),p.boxCenter(:),p.boxSize(:));
    for cluster = 1:numClusters
        if cluster==1 && ~nativeLos
            continue
        end
        phase = exp(-2i*pi*reshape(double(delays(:,:,cluster,k)),[],1)*frequencies);
        portPath = reshape(phase.*reshape(double(raw(:,:,cluster,k)),[],1),size(ports));
        if cluster==1 && blocked(frame)
            portPath = portPath*10^(-p.boxLoss/20);
        end
        ports = ports + portPath;
        coeff = reshape(double(raw(:,:,cluster,k)).*weights(:,frame).',[],1);
        contribution = reshape(phase.*coeff,p.nRx,p.nTx,p.tones);
        response = reshape(sum(contribution,2),p.nRx,p.tones);
        path(:,:,cluster) = response;
        % Displayed powers include the CURRENT TX beam, averaged over RX/tones.
        pathDbm(cluster,frame) = p.txDbm+10*log10(max(mean(abs(response(:)).^2),realmin));
    end
    if ~isempty(nlos)
        [~,idx] = max(pathDbm(nlos,frame));
        strongestNlos(frame) = nlos(idx);
        arrival = lbs(:,nlos)-ue(:,frame);
        arrivalLength = vecnorm(arrival);
        valid = arrivalLength>0;
        clusterAngles(nlos(valid),frame) = asind(arrival(2,valid)./arrivalLength(valid)).';
        angle(3,frame) = clusterAngles(strongestNlos(frame),frame);
    end
    if addedLos
        % Use the geometric departure direction with the actual TX weights.
        txSteering = exp(-1i*axisPhase*txIndex*sind(angle(2,frame)));
        beamResponse = txSteering.'*weights(:,frame);
        magnitude = directField(frame)*10^(-addedLosPathLossDb(frame)/20);
        steering = exp(1i*axisPhase*rxIndex*sind(angle(2,frame)));
        propagation = exp(-2i*pi*(fc+frequencies)*referenceDelay(frame));
        path(:,:,1) = magnitude*beamResponse*steering*propagation;
        portLos = magnitude*(steering*txSteering.').*reshape(propagation,1,1,[]);
        if blocked(frame), portLos = portLos*10^(-p.boxLoss/20); end
        ports = ports + portLos;
    end
    if isLos
        if blocked(frame)
            path(:,:,1) = path(:,:,1)*10^(-p.boxLoss/20);
        end
        losResponse = path(:,:,1);
        pathDbm(1,frame) = p.txDbm+10*log10(max(mean(abs(losResponse(:)).^2),realmin));
    end
    losPilot(:,frame) = pilot*path(1,:,1).';
    losArrayPilot(:,:,frame) = pilot*path(:,:,1);
    bestProjection = -Inf;
    direct = path(:,:,1);
    for other = 2:numClusters
        reflected = path(:,:,other);
        projection = abs(direct(:)'*reflected(:));
        if projection>bestProjection
            bestProjection=projection;
            competitorSlot(frame)=other;
            competitorArrayPilot(:,:,frame)=pilot*reflected;
            competitorCoherence(frame)=projection/max(norm(direct(:))*norm(reflected(:)),realmin);
        end
    end
    H(:,:,frame) = sum(path,3);
    Y(:,:,frame) = pilot*H(:,:,frame)+noiseStd*(randn(p.nRx,p.tones)+1i*randn(p.nRx,p.tones));
    % Per-port MIMO observations retain TX spatial information before beam sum.
    % Radio/M3 candidate powers therefore differ from the displayed beam powers.
    probe = pilot*ports + noiseStd*(randn(probeRng,size(ports))+1i*randn(probeRng,size(ports)));
    weight = reshape(weights(:,frame),1,p.nTx,1);
    delta = Y(:,:,frame)-reshape(sum(probe.*weight,2),p.nRx,p.tones);
    mimoPilot(:,:,:,frame) = probe + reshape(delta,p.nRx,1,p.tones).*conj(weight);
    snapshots = Y(:,center,frame);
    snapshots(:,2:repeats) = pilot*H(:,center,frame)+noiseStd* ...
        (randn(p.nRx,repeats-1)+1i*randn(p.nRx,repeats-1));
    [centerPrincipal(:,frame),centerAngle(frame)] = estimateAngle(snapshots,manifold,scan);
    % Average the UE spatial covariance across tones. The relative phase of
    % different-delay paths rotates across frequency, reducing cross terms.
    [principal(:,frame),angle(1,frame)] = estimateAngle(Y(:,:,frame),manifold,scan);

    indirect = sum(path(:,:,nlos),3);
    components = [path(1,:,1);indirect(1,:);Y(1,:,frame)/pilot]*inverse;
    toaProfile(:,:,frame) = p.txDbm+20*log10(max(abs(components),realmin));
    cleanResponse = H(1,:,frame)*inverse;
    cleanToaProfile(:,frame) = (p.txDbm+20*log10(max(abs(cleanResponse),realmin))).';
    if ~isLos
        toaProfile(1,:,frame) = NaN;
    end
    [~,indices] = max(abs([components(1,:);cleanResponse;components(3,:)]),[],2);
    times = reshape(delayGrid(indices),[],1);
    if ~isLos
        times(1) = NaN;
        indices(1) = NaN;
    end
    toaDiagnostic.peakIndex(:,frame) = indices;
    toaDiagnostic.peakDelayS(:,frame) = times;
    toaDiagnostic.stageShiftS(:,frame) = [times(1)-referenceDelay(frame);diff(times)];
    peakDelay(frame) = times(3);
    range(frame) = c*peakDelay(frame);
    toaDiagnostic.errorS(frame) = peakDelay(frame)-referenceDelay(frame);
    [toaDiagnostic.reason(frame),toaDiagnostic.lateReflection(frame)] = explainToa( ...
        times,referenceDelay(frame),indices(3),components,cleanResponse, ...
        toaDiagnostic.gridStepS,toaDiagnostic.mainLobeHalfWidthS,isLos);

    [~,aoaDiagnostic.cleanDeg(frame)] = estimateAngle(H(:,:,frame),manifold,scan);
    if any(abs(indirect(:))>0)
        [~,aoaDiagnostic.nlosOnlyDeg(frame)] = estimateAngle(indirect,manifold,scan);
    end
    if isLos
        [~,aoaDiagnostic.losOnlyDeg(frame)] = estimateAngle(path(:,:,1),manifold,scan);
    end
    aoaDiagnostic.errorDeg(frame) = angle(1,frame)-angle(2,frame);
    [aoaDiagnostic.reason(frame),aoaDiagnostic.miss(frame)] = explainAoa( ...
        angle(1,frame),angle(2,frame),aoaDiagnostic.losOnlyDeg(frame), ...
        aoaDiagnostic.cleanDeg(frame),aoaDiagnostic.nlosOnlyDeg(frame),angleTolerance,isLos);
end
totalNlosDbm = 10*log10(max(sum(10.^(pathDbm(2:end,:)/10),1,'omitnan'),realmin));
data = struct('parameters',p,'configDirectory',configDir,'scenario',scenario, ...
    'isLos',isLos,'nativeLos',nativeLos,'addedLos',addedLos,'addedLosPathLossDb',addedLosPathLossDb, ...
    'bs',bs,'ue',ue,'time',time,'beamHeadingDeg',heading, ...
    'targetCluster',targetCluster, ...
    'fbs',fbs,'lbs',lbs,'pathDbm',pathDbm,'strongestNlos',strongestNlos, ...
    'nlosClusterAnglesDeg',clusterAngles, ...
    'blocked',blocked,'anglesDeg',angle,'principalVector',principal, ...
    'centerToneAnglesDeg',centerAngle,'centerTonePrincipalVector',centerPrincipal, ...
    'totalNlosDbm',totalNlosDbm,'losMarginDb',pathDbm(1,:)-totalNlosDbm, ...
    'rangeM',range,'trueDistanceM',referenceDistance,'delayS',delays, ...
    'delayGridS',delayGrid,'toaProfileDbm',toaProfile,'cleanToaProfileDbm',cleanToaProfile, ...
    'toaPeakDelayS',peakDelay,'referenceDelayS',referenceDelay, ...
    'toaDiagnostic',toaDiagnostic,'aoaDiagnostic',aoaDiagnostic, ...
    'unambiguousDelayS',unambiguousDelay,'clusterCoefficients',raw, ...
    'losArrayPilot',losArrayPilot,'competitorArrayPilot',competitorArrayPilot, ...
    'competitorSlot',competitorSlot,'competitorCoherence',competitorCoherence, ...
    'H',H,'Y',Y,'losPilotFirstRx',losPilot,'Hhat',Y./pilot,'pilot',pilot,'beamWeights',weights, ...
    'frequencyOffsetsHz',frequencies,'noisePerToneStd',noiseStd,'mimoPilot',mimoPilot);
if isSpecular
    data.fbsTrack=fbsTrack; data.lbsTrack=lbsTrack;
end
end

function lossDb = indoorLosPathLoss(distanceM,carrierGHz)
% Defaults from the InF LOS log-distance model. Honor local overrides.
coefficients = [21.5 31.84 19];
file = '3GPP_38.901_InF_LOS.conf';
if isfile(file)
    config = fileread(file);
    for i = 1:3
        token = regexp(config,['(?m)^\s*PL_' char('A'+i-1) '\s*=\s*([-+\d.eE]+)'], ...
            'tokens','once');
        if ~isempty(token)
            value = str2double(token{1});
            if isfinite(value)
                coefficients(i) = value;
            end
        end
    end
end
lossDb = coefficients(1)*log10(distanceM)+coefficients(2)+coefficients(3)*log10(carrierGHz);
end

function [reason,late] = explainToa(times,reference,index,components,clean,step,mainLobe,isLos)
late = false;
if ~isLos
    reason = "No valid direct ray, strongest peak cannot be labeled LOS";
    return
end
% Attribution uses the complex contributions at the OBSERVED peak.
los = abs(components(1,index))^2;
nlos = abs(components(2,index))^2;
noise = abs(components(3,index)-clean(index))^2;
late = times(3)-times(1)>mainLobe && nlos>2*max(los,noise);
shift = abs(diff(times));
if late
    reason = "Strongest peak selects a late reflection";
    if shift(2)>mainLobe
        reason = reason+"( Noise changes peak selection)";
    end
elseif abs(times(3)-reference)<=step
    reason = "Received peak is within one grid step of geometry";
elseif shift(2)>step/2
    reason = "Noise changes received-peak selection";
elseif shift(1)>step/2
    if shift(1)<=mainLobe
        reason = "Multipath shifts the direct-path peak";
    else
        reason = "Multipath changes the strongest peak, path attribution uncertain";
    end
else
    reason = "Only LOS peak already differs from geometry";
end
end

function [reason,miss] = explainAoa(estimate,truth,losOnly,clean,nlosOnly,tol,isLos)
miss = isLos && abs(estimate-truth)>tol;
if ~isLos
    reason = "No valid direct ray, angle is not a LOS Estimate";
elseif ~miss
    reason = sprintf('Estimate within LOS tolerance %.1f° within tolerance',tol);
elseif abs(clean-truth)<=tol
    reason = "Noise shifts estimate away from LOS";
elseif abs(losOnly-truth)>tol
    reason = "Only LOS estimate already differs from geometry";
elseif abs(nlosOnly-truth)>tol && abs(estimate-nlosOnly)<=tol && abs(clean-nlosOnly)<=tol
    reason = "Principal eigenvector follows NLOS principal direction";
elseif abs(estimate-clean)>tol
    reason = "Multipath and noise jointly affect the principal direction";
else
    reason = "Multipath shifts principal direction away from LOS";
end
end

function power = beamPower(coeff,delays,tones,weights)
power = zeros(1,size(weights,2));
for tone = tones
    response = double(coeff).*exp(-2i*pi*double(delays)*tone);
    power = power+mean(abs(response*weights).^2,1);
end
power = power/numel(tones);
end

function [vector,angle] = estimateAngle(observations,manifold,scan)
covariance = observations*observations'/size(observations,2);
[vectors,values] = eig(covariance,'vector');
[~,index] = max(real(values));
vector = vectors(:,index);
[~,index] = max(abs(manifold'*vector).^2);
angle = scan(index);
end

function antenna = makeArray(count,spacing,roll)
antenna = qd_arrayant('dipole');
if nargin==3 && roll~=0, antenna.rotate_pattern(roll,'x'); end
if count>1
    antenna.copy_element(1,2:count);
end
antenna.element_position = [zeros(1,count); ((0:count-1)-(count-1)/2)*spacing; zeros(1,count)];
end

function hit = intersectsBox(startPoint,endPoint,center,dimensions)
direction = endPoint-startPoint;
low = center-dimensions/2;
high = center+dimensions/2;
entry = 0;
exit = 1;
for axisIndex = 1:3
    if abs(direction(axisIndex))<1e-12
        if startPoint(axisIndex)<low(axisIndex) || startPoint(axisIndex)>high(axisIndex)
            hit = false;
            return
        end
    else
        times = sort(([low(axisIndex) high(axisIndex)]-startPoint(axisIndex))/direction(axisIndex));
        entry = max(entry,times(1));
        exit = min(exit,times(2));
    end
end
hit = entry<=exit;
end

function restore(directory,state)
cd(directory);
rng(state);
end
