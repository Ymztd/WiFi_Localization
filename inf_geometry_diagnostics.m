function fig=inf_geometry_diagnostics(data,estimate,method)
% Four linked diagnostic views for the active InF track and LOS method.
t=data.time(:); n=numel(t); c=299792458;
truthT=data.referenceDelayS(:)*1e9; truthA=data.anglesDeg(2,:).';
estT=estimate(:,3); estA=estimate(:,2);
valid=isfinite(estT)&isfinite(estA);
id=valid & abs(estT-truthT)<=1 & abs(estA-truthA)<=3;
ambiguous=false(n,1);
for k=find(id).'
    for q=2:size(data.delayS,3)
        if abs(estT(k)-1e9*data.delayS(1,1,q,k))<=1 && ...
                abs(estA(k)-data.nlosClusterAnglesDeg(q,k))<=3
            ambiguous(k)=true; break
        end
    end
end
id=id&~ambiguous;
rangeError=c*(estT-truthT)*1e-9;
angleError=estA-truthA;
xy=nan(n,2);
for k=find(valid).'
    slant=c*estT(k)*1e-9;
    dy=-slant*sind(estA(k));
    dx=sqrt(max(0,slant^2-(data.bs(3)-data.ue(3,k))^2-dy^2));
    xy(k,:)=data.bs(1:2).'+[dx,dy];
end
realXY=data.ue(1:2,:).';
posError=vecnorm(xy-realXY,2,2);
bad=id & (abs(rangeError)>.5 | abs(angleError)>2 | posError>1);
good=id&~bad; wrong=valid&~id;
fig=uifigure('Name',['LOS Diagnostics ·' upper(method)],'Position',[100 80 1330 820]);
root=uigridlayout(fig,[3 2]); root.RowHeight={48,'1x','1x'};
header=uilabel(root,'FontSize',15,'FontWeight','bold'); header.Layout.Column=[1 2];
header.Text=sprintf('%s | Unambiguous LOS %d/%d | Parameters after correct selection / position failure %d/%d | Delay ±1 ns, Angle ±3° Truth window', ...
    upper(method),nnz(id),n,nnz(bad),nnz(id));
a1=uiaxes(root); pair=uigridlayout(root,[1 2]); pair.Padding=[0 0 0 0];
a2=uiaxes(pair); a2b=uiaxes(pair); a3=uiaxes(root); a4=uiaxes(root);
% 1. Track errors and status.
hold(a1,'on'); plot(a1,t,rangeError,'Color',[.18 .48 .78],'DisplayName','Signed range error (m)');
plot(a1,t,angleError,'Color',[.82 .4 .03],'DisplayName','Signed angle error (°)');
plot(a1,t,posError,'Color',[.45 .25 .7],'DisplayName','Position error (m)');
yline(a1,.5,':','Range threshold'); yline(a1,2,':','Angle threshold');
scatter(a1,t(good),zeros(nnz(good),1),25,[.1 .6 .3],'filled','DisplayName','Correct path and accurate parameters');
scatter(a1,t(bad),zeros(nnz(bad),1),38,[.85 .2 .15],'filled','DisplayName','Correct path but inaccurate parameters');
scatter(a1,t(wrong),zeros(nnz(wrong),1),30,[.5 .5 .5],'x','DisplayName','Wrong selection');
title(a1,'Frame errors and path selection'); xlabel(a1,'Track time (s)'); pos_plot_style(a1); legend(a1,'Location','best');
% 2. Truth-estimate scatter for unambiguous correct LOS only.
hold(a2,'on'); scatter(a2,truthT(id),estT(id),35,angleError(id),'filled');
lo=min(truthT)-2; hi=max(truthT)+2; plot(a2,[lo hi],[lo hi],'k--');
xlim(a2,[lo hi]); ylim(a2,[lo hi]); colorbar(a2);
title(a2,'LOS Delay'); xlabel(a2,'Truth (ns)'); ylabel(a2,'Estimate (ns)'); pos_plot_style(a2);
hold(a2b,'on'); scatter(a2b,truthA(id),estA(id),35,rangeError(id),'filled');
alo=min(truthA)-3; ahi=max(truthA)+3; plot(a2b,[alo ahi],[alo ahi],'k--');
xlim(a2b,[alo ahi]); ylim(a2b,[alo ahi]); colorbar(a2b); pos_plot_style(a2b);
title(a2b,'LOS Angle'); xlabel(a2b,'Truth (°)'); ylabel(a2b,'Estimate (°)');
% 3. Actual UE track and inferred positions.
hold(a3,'on'); plot(a3,realXY(:,1),realXY(:,2),'-','Color',[0 .48 .55],'LineWidth',2,'DisplayName','UE Truth');
plot(a3,xy(id,1),xy(id,2),'.-','Color',[.49 .24 .69],'DisplayName','Correct LOS inferred position');
for k=find(id).', plot(a3,[realXY(k,1),xy(k,1)],[realXY(k,2),xy(k,2)],'Color',[.75 .75 .75],'HandleVisibility','off'); end
scatter(a3,xy(bad,1),xy(bad,2),35,[.85 .2 .15],'filled','DisplayName','Correct LOS, position error exceeds target');
axis(a3,'equal'); pos_plot_style(a3); legend(a3,'Location','best'); title(a3,'UE True and estimated track'); xlabel(a3,'x (m)'); ylabel(a3,'y (m)');
% 4. Observable failure map, with counts in each cell.
powerGap=data.pathDbm(1,:).'-max(data.pathDbm(2:end,:),[],1).';
delayGap=nan(n,1);
for k=1:n
    later=reshape(data.delayS(1,1,2:end,k),1,[])*1e9-truthT(k);
    later=later(later>0);
    if ~isempty(later), delayGap(k)=min(later); end
end
edgesP=[-inf -10 0 10 inf]; edgesT=[0 5 10 20 inf];
rate=nan(4,4); counts=zeros(4,4);
for i=1:4
 for j=1:4
  mask=id & powerGap>=edgesP(i) & powerGap<edgesP(i+1) & ...
      delayGap>=edgesT(j) & delayGap<edgesT(j+1);
  counts(i,j)=nnz(mask);
  if counts(i,j)>0, rate(i,j)=100*nnz(bad&mask)/counts(i,j); end
 end
end
imagesc(a4,rate,'AlphaData',~isnan(rate)); colormap(a4,parula); colorbar(a4); clim(a4,[0 100]);
a4.XTick=1:4; a4.XTickLabel={'<5','5–10','10–20','≥20'};
a4.YTick=1:4; a4.YTickLabel={'<−10','−10–0','0–10','≥10'};
for i=1:4, for j=1:4, text(a4,j,i,sprintf('%d',counts(i,j)),'HorizontalAlignment','center'); end, end
title(a4,'Correct LOS conditional failure rate (%), numbers indicate frame counts'); xlabel(a4,'Nearest NLOS Delay gap (ns)'); ylabel(a4,'LOS− Strongest NLOS Power (dB)');
end
