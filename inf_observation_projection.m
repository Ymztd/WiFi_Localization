function result=inf_observation_projection(data,frame,errors)
% Transfer paired [range error m, ULA angle error deg] to one reference point.
% This is a geometry diagnostic, not a posterior or a positioning estimator.
result.truth=data.ue(1:2,frame).';
result.range=data.trueDistanceM(frame);
result.angle=data.anglesDeg(2,frame);
result.height=data.ue(3,frame)-data.bs(3);
range=result.range+errors(:,1); angle=result.angle+errors(:,2);
y=-range.*sind(angle);
radicand=range.^2-result.height^2-y.^2;
valid=all(isfinite(errors),2)&range>0&abs(angle)<90&radicand>=0;
result.valid=valid; result.xy=nan(size(errors));
% x>0 half-space and known antenna heights remove geometric ambiguity.
result.xy(valid,:)=data.bs(1:2).'+[sqrt(radicand(valid)),y(valid)];
result.positionError=vecnorm(result.xy-result.truth,2,2);
end
