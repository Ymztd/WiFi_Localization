function metrics = los_quality_metrics(hasLos,truthParams,estimateParams,truthWave,estimatedWave)
% Parameters are [delay in ns, angle in degrees]. Compare complex waveforms.
% A parameter-window match does not establish a unique physical path identity.
metrics.names = ["LOS Correct selection","LOS Waveform recovery","Joint success"];
metrics.limits = [1 3 -10];
metrics.errors = [NaN NaN NaN];
metrics.eligible = [hasLos, hasLos, hasLos];
metrics.passed = false(1,3);
energy = sum(abs(truthWave).^2,'all');
if energy==0
    metrics.eligible(2:3) = false;
end
if hasLos && all(isfinite(estimateParams))
    metrics.errors(1) = estimateParams(1)-truthParams(1);
    angleError = estimateParams(2)-truthParams(2);
    metrics.errors(2) = mod(angleError+180,360)-180;
    metrics.passed(1) = all(abs(metrics.errors(1:2))<=metrics.limits(1:2));
    if metrics.eligible(2) && all(isfinite(estimatedWave),'all')
        metrics.errors(3) = 10*log10(sum(abs(estimatedWave-truthWave).^2,'all')/energy);
        metrics.passed(2) = metrics.errors(3)<=metrics.limits(3);
    end
    metrics.passed(3) = all(metrics.passed(1:2));
end
state = repmat("Fail",1,3);
state(metrics.passed) = "Pass";
state(~metrics.eligible) = "N/A";
metrics.summary = strjoin(metrics.names+": "+state,"  |  ");
end
