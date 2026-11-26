function inf_power_plot(data,file)
%INF_POWER_PLOT Export the LOS and strongest NLOS powers of each frame.
los = data.pathDbm(1,:);
nlos = nan(size(los));
if size(data.pathDbm,1)>1
    nlos = max(data.pathDbm(2:end,:),[],1);
end
f = figure('Visible','off','Color','w','Position',[80 80 1000 520]);
cleanup = onCleanup(@() close(f));
ax = axes(f,'Position',[0.10 0.16 0.86 0.68], ...
    'FontName','Times New Roman','FontSize',13,'LineWidth',2.5, ...
    'GridColor',[0.72 0.75 0.80],'GridAlpha',0.40);
teal = [0.00 0.43 0.48];
orange = [0.78 0.32 0.04];
plot(ax,data.time,los,'Color',teal,'LineWidth',2.5,'DisplayName','LOS Direct path');
hold(ax,'on');
plot(ax,data.time,nlos,'Color',orange,'LineWidth',2.2, ...
    'DisplayName','Strongest per frame NLOS cluster');
delta = nlos-los;
k = find(delta(1:end-1)<=0 & delta(2:end)>0,1);
if ~isempty(k)
    ratio = -delta(k)/(delta(k+1)-delta(k));
    tCross = data.time(k)+ratio*(data.time(k+1)-data.time(k));
    xline(ax,tCross,'--',sprintf('First crossover near %.2f s',tCross), ...
        'Color',[0.34 0.37 0.43],'LineWidth',1.25,'LabelOrientation','horizontal', ...
        'LabelVerticalAlignment','bottom','HandleVisibility','off');
end
pos_plot_style(ax);
box(ax,'on');
xlim(ax,data.time([1 end]));
xlabel(ax,'Time (s)');
ylabel(ax,'single UE element mean received power (dBm)');
legend(ax,'Location','southwest','Box','off');
scenario = erase(string(data.parameters.scenario),"3GPP_38.901_");
title(ax,scenario+": LOS and strongest NLOS power over time",'Interpreter','none', ...
    'FontSize',17);
pos_plot_style(ax);
exportgraphics(f,file,'Resolution',180);
end
