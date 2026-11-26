function [raw,delays,fbs,lbs,ue,bs] = specular_channel_setup(p)
% Deterministic image-source model: LOS, side walls, and optional floor.
% Geometry sets excess delay and BOTH array angles; no independent knobs.
c=299792458; fc=p.fcGHz*1e9;
bs=p.bs(:); ue=p.ueStart(:)+(p.ueEnd(:)-p.ueStart(:))*linspace(0,1,p.frames);
if min([bs(3),ue(3,:)])<=0 || any(vecnorm(ue-bs)<.1)
    error('Use positive antenna heights and at least 0.1 m TX-RX distance.');
end
h=p.wallOffset;
if any(abs([bs(2),ue(2,:)])>=h)
    error('Side-wall offset must exceed the absolute TX and RX y coordinates.');
end
count=str2double(extractAfter(string(p.scenario),'Specular_'));
validateattributes(count,{'double'},{'scalar','integer','>=',1,'<=',3});
L=count+1; raw=complex(zeros(p.nRx,p.nTx,L,p.frames));
delays=zeros(p.nRx,p.nTx,L,p.frames);
fbs=zeros(3,L,p.frames); lbs=fbs;
rx=(0:p.nRx-1)'-(p.nRx-1)/2; tx=(0:p.nTx-1)'-(p.nTx-1)/2;
for k=1:p.frames
    for path=1:L
        image=bs;
        if path==2, image(2)=2*h-bs(2); plane=2; level=h; end
        if path==3, image(2)=-2*h-bs(2); plane=2; level=-h; end
        if path==4, image(3)=-bs(3); plane=3; level=0; end
        d=norm(ue(:,k)-image); arrival=image-ue(:,k); departure=ue(:,k)-bs;
        gain=c/(4*pi*fc*d);
        if path>1
            t=(level-image(plane))/(ue(plane,k)-image(plane));
            bounce=image+t*(ue(:,k)-image);
            fbs(:,path,k)=bounce; lbs(:,path,k)=bounce;
            arrival=bounce-ue(:,k); departure=bounce-bs;
            % Negative real reflection coefficient: fixed pi phase shift.
            gain=-p.reflectionMagnitude*gain;
        else
            gain=gain*10^(-p.directLossDb/20);
        end
        ar=asind(arrival(2)/norm(arrival)); at=asind(departure(2)/norm(departure));
        raw(:,:,path,k)=gain*exp(-2i*pi*fc*d/c)* ...
            (exp(2i*pi*.45*rx*sind(ar))*exp(2i*pi*.45*tx*sind(at)).');
        delays(:,:,path,k)=d/c;
    end
end
end
