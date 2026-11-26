function pos_plot_inspector(fig)
% Add editing access to every axes, including panels styled by other views.
if isempty(fig) || ~isgraphics(fig), return, end
tag='PosPlotEditorMenu';
if ~isequal(getappdata(fig,'PosPlotEditorVersion'),2)
    delete(findall(fig,'Type','uimenu','Tag',tag));
    for ax=reshape(findall(fig,'Type','axes'),1,[])
        context=getappdata(ax,'PosPlotEditorContext');
        if ~isempty(context) && isgraphics(context), delete(context); end
        if isappdata(ax,'PosPlotEditorContext'), rmappdata(ax,'PosPlotEditorContext'); end
    end
    setappdata(fig,'PosPlotEditorVersion',2);
end
if isempty(findall(fig,'Type','uimenu','Tag',tag))
    menu=uimenu(fig,'Text','Plot editor','Tag',tag);
    uimenu(menu,'Text','Open editable plot...','MenuSelectedFcn',@(~,~) choosePlot(fig));
    uimenu(menu,'Text','Open all plots as editable figures', ...
        'MenuSelectedFcn',@(~,~) openAll(fig));
end
allAxes=findall(fig,'Type','axes');
for ax=reshape(allAxes,1,[])
    context=getappdata(ax,'PosPlotEditorContext');
    if isempty(context) || ~isgraphics(context)
        context=uicontextmenu(fig);
        uimenu(context,'Text','Open editable plot / Property Inspector', ...
            'MenuSelectedFcn',@(~,~) pos_editable_plot(ax));
        uimenu(context,'Text','Inspect live axes (refresh may overwrite edits)', ...
            'MenuSelectedFcn',@(~,~) inspect(ax));
        uimenu(context,'Text','Inspect live title', ...
            'MenuSelectedFcn',@(~,~) inspect(ax.Title));
        setappdata(ax,'PosPlotEditorContext',context);
    end
    ax.ContextMenu=context;
    % Make the same entry reachable by right-clicking a curve or title.
    children=findall(ax,'-property','ContextMenu');
    set(children,'ContextMenu',context);
end
end

function choosePlot(fig)
axesList=findall(fig,'Type','axes');
if isempty(axesList), return, end
names=cell(1,numel(axesList));
for k=1:numel(axesList)
    value=strjoin(string(axesList(k).Title.String)," ");
    if strlength(value)==0, value="Untitled axes"; end
    names{k}=sprintf('%d  %s',k,value);
end
picker=uifigure('Name','Select plot to edit','Position',[180 180 700 170]);
grid=uigridlayout(picker,[3 1]);grid.RowHeight={25,35,35};
uilabel(grid,'Text','Select a plot. The editor opens native MATLAB graphics.');
choice=uidropdown(grid,'Items',names,'ItemsData',1:numel(axesList));
uibutton(grid,'Text','Open Property Inspector','ButtonPushedFcn',@open);
    function open(~,~)
        ax=axesList(choice.Value);
        if isgraphics(ax), pos_editable_plot(ax); end
    end
end

function openAll(fig)
axesList=findall(fig,'Type','axes');
for ax=reshape(axesList,1,[])
    pos_editable_plot(ax,false);
end
end
