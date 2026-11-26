function pos_plot_style(ax)
%POS_PLOT_STYLE Consistent axes appearance for plots and GUI redraws.
for k = 1:numel(ax)
    a = ax(k);
    set(a, 'FontName', 'Times New Roman', 'FontSize', 13, ...
        'LineWidth', 2.5, 'Box', 'on', ...
        'XGrid', 'off', 'YGrid', 'off', 'ZGrid', 'off', ...
        'XMinorGrid', 'off', 'YMinorGrid', 'off', 'ZMinorGrid', 'off', ...
        'TitleFontSizeMultiplier', 1.1, 'LabelFontSizeMultiplier', 1.1);
    set(findall(a, '-property', 'FontName'), 'FontName', 'Times New Roman');
    labels = [a.Title, a.XLabel, a.YLabel, a.ZLabel];
    set(labels, 'FontName', 'Times New Roman', 'FontSize', 14);
    fig = ancestor(a, 'figure');
    if ~isempty(fig)
        set(findall(fig, '-property', 'FontName'), 'FontName', 'Times New Roman');
        legends = findall(fig, 'Type', 'legend');
        set(legends, 'FontName', 'Times New Roman', 'FontSize', 11);
        pos_plot_inspector(fig);
        bars = findall(fig, 'Type', 'colorbar');
        set(bars, 'FontName', 'Times New Roman', 'FontSize', 12);
    end
end
end

