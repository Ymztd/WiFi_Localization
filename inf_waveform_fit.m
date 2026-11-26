function [parts, delays, angles, selectionOrder] = inf_waveform_fit(Y,frequency,noiseStd)
% Sparse delay-angle fit using only the received pilot and array calibration.
[nRx,nTones] = size(Y);
nFFT = 4*2^nextpow2(nTones);
bins = mod(-floor(nTones/2):ceil(nTones/2)-1,nFFT)+1;
delayGrid = (0:nFFT-1)/(nFFT*(frequency(2)-frequency(1)));
index = (0:nRx-1)'-(nRx-1)/2;
angleGrid = -90:2:90;
steering = exp(2i*pi*0.45*index*sind(angleGrid));
atoms = complex(zeros(numel(Y),0));
delays = [];
angles = [];
residual = Y;
% A conservative correlated-noise peak threshold, in projection power.
threshold = 2*noiseStd^2*log(numel(delayGrid)*size(steering,2)/0.01);
for step = 1:12
    padded = complex(zeros(nRx,nFFT));
    padded(:,bins) = residual;
    spectrum = steering'*ifft(padded,[],2);
    projection = abs(spectrum).^2*nFFT^2/numel(Y);
    [peak,linear] = max(projection(:));
    if peak <= threshold
        break
    end
    [angleBin,delayBin] = ind2sub(size(projection),linear);
    delay = delayGrid(delayBin);
    response = steering(:,angleBin)*exp(-2i*pi*frequency*delay);
    next = [atoms,response(:)];
    if rcond(next'*next)<1e-9
        break
    end
    atoms = next;
    delays(end+1) = delay; %#ok<AGROW>
    angles(end+1) = angleGrid(angleBin); %#ok<AGROW>
    coefficients = atoms\Y(:);
    residual = reshape(Y(:)-atoms*coefficients,size(Y));
end
[delays,order] = sort(delays);
selectionOrder = order;
angles = angles(order);
parts = complex(zeros(nTones,numel(order)));
if ~isempty(order)
    firstRx = atoms(1:nRx:end,:).*coefficients.';
    parts = firstRx(:,order);
end
end
