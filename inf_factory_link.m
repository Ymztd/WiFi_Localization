function p = inf_factory_link(p)
% One conditional link realization for the track. Auto samples at its start.
f=inf_factory_preset(p.factoryId);
h=[p.bs(3),p.ueStart(3),p.ueEnd(3)];
hh=strcmp(f.id,'InF-HH');
if any(~isfinite(h) | h<=0 | h>=f.hallM(3)) || ...
        (endsWith(f.id,'L') && h(1)>=f.clutterHeightM) || ...
        (endsWith(f.id,'H') && h(1)<=f.clutterHeightM) || ...
        (~hh && any(h(2:3)>=f.clutterHeightM)) || (hh && any(h(2:3)<=f.clutterHeightM))
    error('inf:Height','Antenna heights conflict with %s (clutter %g m, ceiling %g m).',f.id,f.clutterHeightM,f.hallM(3));
end
prob=1;
if ~hh
    scale=-f.sizeM/log1p(-f.density);
    if endsWith(f.id,'H')
        scale=scale*(h(1)-h(2))/(f.clutterHeightM-h(2));
    end
    prob=exp(-norm(p.bs(1:2)-p.ueStart(1:2))/scale);
end
mode=validatestring(p.linkMode,{'LOS','NLOS','Auto'});
if hh && strcmp(mode,'NLOS'), error('inf:Link','InF-HH requires LOS.'); end
los=strcmp(mode,'LOS');
if strcmp(mode,'Auto')
    stream=RandStream('mt19937ar','Seed',mod(double(p.seed)+314159,2^32));
    los=rand(stream)<prob;
end
if los
    p.scenario='3GPP_38.901_InF_LOS';
else
    p.scenario=['3GPP_38.901_InF_NLOS_' f.id(end-1:end)];
end
p.addPhysicalLos=false;
f.losProbabilityAtStart=prob;
dims=f.hallM;
ratio=prod(dims)/(2*(dims(1)*dims(2)+dims(1)*dims(3)+dims(2)*dims(3)));
if los, f.logDelaySpreadMean=log10(26*ratio+14)-9.35;
else, f.logDelaySpreadMean=log10(30*ratio+32)-9.44; end
p.factory=f;
end
