function results = two_path_separation_demo(outputFile)
% 1 LOS + 1 NLOS. Known model order, calibrated CSI, grid-based simulation.
% results = two_path_separation_demo("two_path_separation.png") saves the figure.
if nargin < 1
    outputFile = "";
end
rng(17);
bandwidth = 80e6;
tones = 64;
frequency = bandwidth*((0:tones-1)'-(tones-1)/2)/tones;
delayNs = 0:1:64;
angleDeg = -60:10:60;
[tau, theta] = ndgrid(delayNs, angleDeg);
delayResponse = exp(-2i*pi*frequency*delayNs*1e-9);
atoms = complex(zeros(3*tones, numel(tau)));
for k = 1:numel(tau)
    spatial = exp(-1i*pi*(0:2)*sind(theta(k)));
    response = exp(-2i*pi*frequency*tau(k)*1e-9)*spatial;
    atoms(:,k) = response(:)/sqrt(numel(response));
end
gram = atoms'*atoms;
denominator = 1-abs(gram).^2;
validPairs = triu(denominator > 1e-10,1);
denominator(~validPairs) = 1;

% LOS is at 12 ns and -10 deg in every trial. CSI is one noisy snapshot.
los = find(tau==12 & theta==-10);
delayGap = [0 1 2 3 5 8 12 16 24 32];
angleGap = [0 40 40 40];
relativeDb = [0 0 15 15]; % NLOS power relative to LOS
snrDb = [20 20 20 0];    % NLOS SNR per antenna and tone
labels = ["Same AoA", "40 deg apart", "40 deg, LOS 15 dB weaker", ...
          "40 deg, LOS 15 dB weaker, NLOS SNR 0 dB"];
trials = 40;
delayRate = zeros(numel(angleGap),numel(delayGap));
jointRate = delayRate;
rho = delayRate;
for scenario = 1:numel(angleGap)
    for d = 1:numel(delayGap)
        nlos = find(tau==12+delayGap(d) & theta==-10+angleGap(scenario));
        rho(scenario,d) = abs(gram(los,nlos));
        if los==nlos
            continue % One observable atom and infinitely many gain splits.
        end
        for trial = 1:trials
            [csi, ~] = receive(atoms(:,[los nlos]),relativeDb(scenario),snrDb(scenario));
            detected = delayPeaks(csi(1:tones),delayResponse);
            truth = [tau([los;nlos]),theta([los;nlos])];
            if delayGap(d)>0 && numel(detected)==2
                delayRate(scenario,d) = delayRate(scenario,d) + ...
                    all(abs(sort(delayNs(detected))-sort(truth(:,1)).')<=2);
            end
            pair = fitPair(csi,atoms,gram,denominator,validPairs);
            estimate = [tau(pair),theta(pair)];
            jointRate(scenario,d) = jointRate(scenario,d) + ...
                (matches(estimate,truth) || matches(flipud(estimate),truth));
        end
    end
end
delayRate = delayRate/trials;
jointRate = jointRate/trials;

% Show a close-delay example with angular diversity.
nlos = find(tau==15 & theta==30);
[csi, components] = receive(atoms(:,[los nlos]),0,20);
[pair, gain] = fitPair(csi,atoms,gram,denominator,validPairs);
estimated = atoms(:,pair).*gain.';
fig = figure('Name','Two-path CSI separation','Color','w','Position',[100 100 1150 720]);
layout = tiledlayout(fig,2,2,'TileSpacing','compact');
ax = nexttile(layout);
semilogy(ax,delayNs,abs(delayResponse'*[components(1:tones,:),csi(1:tones)]));
xlabel(ax,'Delay (ns)'); ylabel(ax,'Matched-filter magnitude');
title(ax,'Single-antenna delay profile, 3 ns gap');
legend(ax,{'LOS truth','NLOS truth','Received'},'Location','best'); pos_plot_style(ax);
ax = nexttile(layout);
imageData = reshape(abs(atoms'*csi),numel(delayNs),[]);
imagesc(ax,delayNs,angleDeg,imageData.'); axis(ax,'xy'); hold(ax,'on');
plot(ax,tau([los;nlos]),theta([los;nlos]),'wo','MarkerSize',11,'LineWidth',1.5);
plot(ax,tau(pair),theta(pair),'rx','MarkerSize',12,'LineWidth',2);
xlabel(ax,'Delay (ns)'); ylabel(ax,'AoA (deg)');
title(ax,'Joint response and two-path fit');
legend(ax,{'Truth','Joint fit'},'Location','best'); colorbar(ax);
ax = nexttile(layout);
plot(ax,delayGap,100*delayRate.','o--');
xlabel(ax,'Delay gap (ns)'); ylabel(ax,'Two delays recovered (%)');
title(ax,'Single-antenna delay peaks'); ylim(ax,[-4 104]); pos_plot_style(ax);
ax = nexttile(layout);
plot(ax,delayGap,100*jointRate.','o-');
xlabel(ax,'Delay gap (ns)'); ylabel(ax,'Two delay–AoA pairs recovered (%)');
title(ax,'Joint two-path least squares'); ylim(ax,[-4 104]); pos_plot_style(ax);
legend(ax,labels,'Location','southeast','FontSize',11);
title(layout,'80 MHz, 64 tones, 3 half-wavelength receive antennas');
if strlength(string(outputFile))>0
    exportgraphics(fig,outputFile,'Resolution',150);
end

results = struct('delayGapNs',delayGap,'labels',labels,'coherence',rho, ...
    'delayRate',delayRate,'jointRate',jointRate,'trials',trials, ...
    'frequencyHz',frequency,'exampleTruth',[tau([los;nlos]),theta([los;nlos])], ...
    'exampleEstimate',[tau(pair),theta(pair)],'exampleReceived',reshape(csi,tones,3), ...
    'exampleTrueComponents',reshape(components,tones,3,2), ...
    'exampleEstimatedComponents',reshape(estimated,tones,3,2));
end

function [csi, components] = receive(atoms,relativeDb,snrDb)
scale = sqrt(size(atoms,1));
gain = scale*[10^(-relativeDb/20), exp(2i*pi*rand)];
components = atoms.*gain;
noise = 10^(-snrDb/20)*(randn(size(atoms,1),1)+1i*randn(size(atoms,1),1))/sqrt(2);
csi = sum(components,2)+noise;
end

function indices = delayPeaks(csi,response)
power = abs(response'*csi).^2;
previous = [-Inf;power(1:end-1)];
following = [power(2:end);-Inf];
indices = find(power>previous & power>following);
[~, order] = sort(power(indices),'descend');
indices = indices(order(1:min(2,end)));
end

function [pair,gain] = fitPair(csi,atoms,gram,denominator,validPairs)
projection = atoms'*csi;
% Squared projection onto span(a_i,a_j), evaluated for each distinct pair.
power = abs(projection).^2+abs(projection.').^2 ...
    -2*real(conj(projection).*gram.*projection.');
power = power./denominator;
power(~validPairs) = -Inf;
[~, position] = max(power(:));
[first, second] = ind2sub(size(power),position);
pair = [first;second];
if nargout>1
    gain = atoms(:,pair)\csi;
end
end

function yes = matches(estimate,truth)
yes = all(abs(estimate-truth)<=[2 5],'all');
end

