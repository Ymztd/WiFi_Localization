function editor=pos_editable_plot(source,openInspector)
% Copy actual graphics into a standard MATLAB figure for persistent editing.
% Edits belong to this snapshot. Save FIG to retain all editable objects.
if nargin<2, openInspector=true; end
if ~isgraphics(source,'axes'), error('Select a valid plot axes.'); end
editor=figure('Name','Editable plot snapshot','NumberTitle','off', ...
    'Position',[100 100 1100 740],'Color','white','MenuBar','figure','ToolBar','figure');
try
    % Build a native axes. copyobj(UIAxes,figure) retains the UIAxes class.
    target=axes('Parent',editor);
    original=source.Children;
    copied=copyobj(original,target);
    copyProperties(source,target,{'Children','Parent','Title','Subtitle', ...
        'XLabel','YLabel','ZLabel','Legend','Colorbar','Position','InnerPosition', ...
        'OuterPosition','Units','Layout','Toolbar','Interactions','ContextMenu', ...
        'UIContextMenu','ButtonDownFcn','CreateFcn','DeleteFcn','SizeChangedFcn', ...
        'NextPlot','UserData','Tag'});
    for name={'Title','Subtitle','XLabel','YLabel','ZLabel'}
        if isprop(source,name{1}) && isprop(target,name{1})
            copyProperties(source.(name{1}),target.(name{1}), ...
                {'Parent','Children','ContextMenu','UIContextMenu','ButtonDownFcn', ...
                'CreateFcn','DeleteFcn','Position','Units','UserData'});
        end
    end
    if ~isempty(source.Legend) && isgraphics(source.Legend)
        labels=source.Legend.String;
        handles=gobjects(0);
        for h=reshape(source.Legend.PlotChildren,1,[])
            index=find(original==h,1);
            if ~isempty(index), handles(end+1)=copied(index); end
        end
        if numel(handles)==numel(labels)
            lg=legend(target,handles,labels);
        else
            lg=legend(target,labels);
        end
        copyProperties(source.Legend,lg,{'Parent','Children','PlotChildren', ...
            'Position','Units','Layout','ContextMenu','UIContextMenu','UserData', ...
            'ButtonDownFcn','CreateFcn','DeleteFcn'});
    end
    if ~isempty(source.Colorbar) && isgraphics(source.Colorbar)
        cb=colorbar(target);
        copyProperties(source.Colorbar,cb,{'Parent','Children','Axes','Position', ...
            'Units','Layout','ContextMenu','UIContextMenu','UserData', ...
            'ButtonDownFcn','CreateFcn','DeleteFcn'});
        copyProperties(source.Colorbar.Label,cb.Label, ...
            {'Parent','Children','Position','Units','ContextMenu','UIContextMenu'});
    end
    target.Units='normalized';
    target.PositionConstraint='innerposition';
    target.InnerPosition=[.14 .16 .74 .70];
    % Context menus belong to the source figure and cannot be shared.
    copiedMenus=findall(editor,'Type','uicontextmenu');
    delete(copiedMenus);
    items=findall(editor,'-property','ContextMenu');
    set(items,'ContextMenu',[]);
    target.Tag='EditablePlotAxes';
    menu=uimenu(editor,'Text','Plot editor');
    uimenu(menu,'Text','Inspect axes','MenuSelectedFcn',@(~,~) inspect(target));
    uimenu(menu,'Text','Inspect title','MenuSelectedFcn',@(~,~) inspect(target.Title));
    uimenu(menu,'Text','Inspect x label','MenuSelectedFcn',@(~,~) inspect(target.XLabel));
    uimenu(menu,'Text','Inspect y label','MenuSelectedFcn',@(~,~) inspect(target.YLabel));
    uimenu(menu,'Text','Inspect curves...','MenuSelectedFcn',@(~,~) inspectCurves(target));
    if ~isempty(target.Legend)
        uimenu(menu,'Text','Inspect legend','MenuSelectedFcn',@(~,~) inspect(target.Legend));
    end
    uimenu(menu,'Text','Save editable FIG...','Separator','on','MenuSelectedFcn',@(~,~) saveFigure(editor));
    uimenu(menu,'Text','Export image or vector PDF...','MenuSelectedFcn',@(~,~) exportFigure(editor));
    editor.UserData=struct('axes',target,'sourceTag',source.Tag);
    plotedit(editor,'on');
    if openInspector, inspect(target); end
catch exception
    delete(editor);
    rethrow(exception)
end
end

function inspectCurves(ax)
objects=ax.Children;
if isempty(objects), return, end
names=cell(1,numel(objects));
for k=1:numel(objects)
    label="";
    if isprop(objects(k),'DisplayName'), label=string(objects(k).DisplayName); end
    names{k}=sprintf('%d  %s  %s',k,objects(k).Type,label);
end
[index,ok]=listdlg('ListString',names,'SelectionMode','single', ...
    'Name','Inspect plot object','ListSize',[460 280]);
if ok, inspect(objects(index)); end
end

function saveFigure(fig)
[file,folder]=uiputfile('*.fig','Save editable plot','edited_plot.fig');
if ischar(file), savefig(fig,fullfile(folder,file)); end
end

function exportFigure(fig)
[file,folder]=uiputfile({'*.png','PNG image';'*.pdf','Vector PDF'}, ...
    'Export edited plot','edited_plot.png');
if ~ischar(file), return, end
path=fullfile(folder,file);
[~,~,ext]=fileparts(path);
if strcmpi(ext,'.pdf')
    exportgraphics(fig,path,'ContentType','vector');
else
    exportgraphics(fig,path,'Resolution',300);
end
end

function copyProperties(source,target,excluded)
% Only transfer editable properties shared by the native graphics object.
values=get(source);
names=intersect(fieldnames(values),fieldnames(set(target)),'stable');
names=setdiff(names,excluded,'stable');
% Restore automatic/manual modes after their corresponding numeric values.
modes=endsWith(names,'Mode');
names=[names(~modes);names(modes)];
for k=1:numel(names)
    try
        set(target,names{k},values.(names{k}));
    catch
        % UI-only property values may be unsupported by native axes.
    end
end
end
