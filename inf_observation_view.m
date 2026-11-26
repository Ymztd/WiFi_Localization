function fig=inf_observation_view(data,estimate,method,frame)
% Actual paired residuals; optional repeated receiver-noise experiments.
% Track errors are non-IID and vary with channel/geometry. Do not call their
% transferred spread a fixed-point confidence region or a fusion gain.
fig=uifigure('Name',['Observation contribution | ' upper(method)],'Position',[50 45 1450 930]);
g=uigridlayout(fig,[5 3]);g.RowHeight={38,52,55,'1x','1x'};
tools=uigridlayout(g,[1 8],'Padding',[0 0 0 0]);tools.Layout.Column=[1 3];
tools.ColumnWidth={45,65,190,210,60,60,190,'1x'};
uilabel(tools,'Text','Frame');
frameBox=uieditfield(tools,'numeric','Value',frame,'Limits',[1,numel(data.time)],'RoundFractionalValues','on','ValueChangedFcn',@changeFrame,'Tag','ObservationFrame');
scope=uidropdown(tools,'Items',{'All finite selections','LOS-window matches only'},'ValueChangedFcn',@draw,'Tag','ObservationScope');
source=uidropdown(tools,'Items',{'Track residuals','Fixed-channel noise trials'},'ValueChangedFcn',@draw,'Tag','ObservationSource');
uilabel(tools,'Text','Trials');
trials=uieditfield(tools,'numeric','Value',30,'Limits',[3 300],'RoundFractionalValues','on');
run=uibutton(tools,'Text','Run noise trials','ButtonPushedFcn',@simulate,'Tag','RunObservationTrials');
uibutton(tools,'Text','Export CSV','ButtonPushedFcn',@exportRows);
info=uilabel(g,'WordWrap','on','Tag','ObservationSummary');info.Layout.Row=2;info.Layout.Column=[1 3];
note=uilabel(g,'WordWrap','on','Text','Known heights and x > BS x assumed. ULA angle is not horizontal azimuth. Paired errors stay paired. Track transfer is descriptive, not a confidence region or measured fusion gain. Snapshot: reopen after channel or estimator changes.');
note.Layout.Row=3;note.Layout.Column=[1 3];
ax=gobjects(1,6);
for i=1:6
    p=uipanel(g,'BorderType','none','AutoResizeChildren','off');p.Layout.Row=4+floor((i-1)/3);p.Layout.Column=1+mod(i-1,3);
    % Use the same inner rectangle for all six panels, including map views.
    ax(i)=uiaxes(p,'Units','normalized','InnerPosition',[.15 .20 .81 .68], ...
        'PositionConstraint','innerposition','FontSize',13,'TitleFontSizeMultiplier',1,'Tag',sprintf('ObservationAxes%d',i));
end
noiseErrors=[]; noiseFrame=NaN; active=[]; activeProjection=[];
truthT=data.referenceDelayS(:)*1e9;truthA=data.anglesDeg(2,:).';
trackErrors=[.299792458*(estimate(:,3)-truthT),mod(estimate(:,2)-truthA+180,360)-180];
if ~ismember(method,{'omp','spring'})
    run.Enable='off';run.Tooltip='Noise trials currently support OMP and SPRING+ receiver CSI. Track residuals support all estimators.';
end
fig.UserData=struct;draw();
    function changeFrame(~,~)
        frame=frameBox.Value;draw();
    end
    function draw(~,~)
        active=[];activeProjection=[];
        for a=ax,cla(a);end
        if ~data.isLos
            info.Text='N/A: native NLOS has no physical LOS reference.';return
        end
        if data.ue(1,frame)<=data.bs(1)
            info.Text='N/A: this view assumes the known x > BS x half-space.';return
        end
        repeated=strcmp(source.Value,'Fixed-channel noise trials');
        if repeated
            if isempty(noiseErrors)||noiseFrame~=frame
                info.Text='Run noise trials at this frame first. The physical channel is held fixed; only receiver noise changes.';return
            end
            errors=noiseErrors;label='Frozen-channel noise trials';
        else
            errors=trackErrors;label='Track residual transfer (non-IID)';
        end
        finite=all(isfinite(errors),2);
        matched=finite&abs(errors(:,1))<=.299792458&abs(errors(:,2))<=3;
        selected=finite;
        if strcmp(scope.Value,'LOS-window matches only'),selected=matched;end
        e=errors(selected,:);active=e;
        if isempty(e)
            info.Text=sprintf('%s | finite %d/%d | LOS-window matches %d | no eligible samples',label,nnz(finite),size(errors,1),nnz(matched));
            fig.UserData=struct('errors',e,'source',label,'frame',frame, ...
                'totalCount',size(errors,1),'finiteCount',nnz(finite),'matchCount',nnz(matched));return
        end
        projection=inf_observation_projection(data,frame,e);activeProjection=projection;
        points=projection.xy(projection.valid,:);pe=projection.positionError(projection.valid);
        span=3;
        if ~isempty(pe),span=max(3,1.3*quantile(pe,.95));end
        center=projection.truth;bx=data.bs(1);by=data.bs(2);
        xx=linspace(max(bx+.001,center(1)-span),center(1)+span,150);yy=linspace(center(2)-span,center(2)+span,150);
        [X,Y]=meshgrid(xx,yy);R=sqrt((X-bx).^2+(Y-by).^2+projection.height^2);
        A=asind((by-Y)./R);
        ar=projection.angle+quantile(e(:,2),[.05 .95]);rr=projection.range+quantile(e(:,1),[.05 .95]);
        % Marginal central-90% residual bands are descriptive, not joint 90%.
        bands={(A>=ar(1)&A<=ar(2)),(R>=rr(1)&R<=rr(2))};
        observables={A,R};bounds={ar,rr};
        for j=1:2
            % Grid-quantized estimators may have exactly zero sample spread.
            % Draw the constraint itself instead of inventing a band width.
            if any(bands{j},'all') && ~all(bands{j},'all')
                contourf(ax(j),X,Y,double(bands{j}),[-.5 .5 1.5],'LineStyle','none');
            end
            colormap(ax(j),[.96 .97 .98;.79 .87 .94]);clim(ax(j),[0 1]);hold(ax(j),'on');
            for boundary=unique(bounds{j})
                contour(ax(j),X,Y,observables{j},[boundary boundary],'LineColor',[.18 .4 .65]);
            end
        end
        hold(ax(3),'on');
        if ~isempty(points)
            scatter(ax(3),points(:,1),points(:,2),18,[.15 .45 .6],'filled','MarkerFaceAlpha',.4);
        end
        for j=1:3
            hold(ax(j),'on');plot(ax(j),center(1),center(2),'kx','MarkerSize',10,'LineWidth',2);
            axis(ax(j),'normal');xlim(ax(j),xx([1 end]));ylim(ax(j),yy([1 end]));xlabel(ax(j),'x (m)');ylabel(ax(j),'y (m)');pos_plot_style(ax(j));
        end
        title(ax(1),'Angle only | central 90% marginal band');title(ax(2),'Range only | central 90% marginal band');title(ax(3),'Joint | paired-error position spread');
        scatter(ax(4),e(:,1),e(:,2),22,[.42 .3 .65],'filled');xlabel(ax(4),'Range error (m)');ylabel(ax(4),'ULA angle error (deg)');title(ax(4),'Actual paired parameter errors');pos_plot_style(ax(4));
        plot(ax(5),errors(:,1),'-o','DisplayName','Range error (m)');hold(ax(5),'on');plot(ax(5),errors(:,2),'-s','DisplayName','Angle error (deg)');
        xlabel(ax(5),'Trial index / track frame');title(ax(5),'Original errors | before scope filtering');legend(ax(5),'Location','best');pos_plot_style(ax(5));
        if ~isempty(pe)
            stairs(ax(6),sort(pe),(1:numel(pe))/numel(pe),'LineWidth',1.5);
        end
        xlabel(ax(6),'Position error at reference geometry (m)');ylabel(ax(6),'Empirical CDF');ylim(ax(6),[0 1.05]);title(ax(6),'Joint reconstruction | valid geometry only');pos_plot_style(ax(6));
        drawnow limitrate nocallbacks;
        set(ax,'Units','normalized','PositionConstraint','innerposition', ...
            'InnerPosition',[.15 .20 .81 .68]);
        rmse=NaN;if ~isempty(pe),rmse=sqrt(mean(pe.^2));end
        info.Text=sprintf('%s | %s | frame %d | finite %d/%d; matched %d; used %d; invalid geometry %d | mean errors: range %+.3f m / angle %+.3f deg | joint RMSE %.3f m', ...
            label,upper(method),frame,nnz(finite),size(errors,1),nnz(matched),size(e,1),nnz(~projection.valid),mean(e(:,1)),mean(e(:,2)),rmse);
        fig.UserData=struct('errors',e,'source',label,'frame',frame,'projection',projection,'finiteCount',nnz(finite),'matchCount',nnz(matched),'totalCount',size(errors,1));
    end
    function simulate(~,~)
        if ~ismember(method,{'omp','spring'}),return,end
        run.Enable='off';restore=onCleanup(@() set(run,'Enable','on'));
        N=trials.Value; noiseErrors=nan(N,2);noiseFrame=frame;
        stream=RandStream('mt19937ar','Seed',mod(double(data.parameters.seed)+frame+5081,2^32));
        clean=data.pilot*data.H(:,:,frame);s=data.noisePerToneStd;f=data.frequencyOffsetsHz;
        for j=1:N
            if strcmp(method,'spring')
                % Each independent trial is a fresh three-packet frozen burst.
                Y=repmat(clean,1,1,3);Y=Y+s*(randn(stream,size(Y))+1i*randn(stream,size(Y)));
                fits=inf_spring_plus_fit(Y,f,s);fit=fits(3);t=fit.delays;a=fit.angles;pick=fit.los;
            else
                Y=clean+s*(randn(stream,size(clean))+1i*randn(stream,size(clean)));
                [~,t,a]=inf_waveform_fit(Y,f,s);pick=double(~isempty(t));
            end
            if pick>0
                noiseErrors(j,:)=[299792458*(t(pick)-data.referenceDelayS(frame)),mod(a(pick)-data.anglesDeg(2,frame)+180,360)-180];
            end
            info.Text=sprintf('Frozen-channel %s trials: %d/%d',upper(method),j,N);drawnow limitrate nocallbacks;
        end
        source.Value='Fixed-channel noise trials';draw();
    end
    function exportRows(~,~)
        if isempty(active)||isempty(activeProjection),return,end
        [file,folder]=uiputfile('*.csv','Export paired observation residuals','observation_contribution.csv');
        if ~ischar(file),return,end
        r=activeProjection;
        tableOut=table(active(:,1),active(:,2),r.xy(:,1),r.xy(:,2),r.positionError,r.valid, ...
            'VariableNames',{'RangeError_m','AngleError_deg','EstimatedX_m','EstimatedY_m','PositionError_m','ValidGeometry'});
        tableOut.Source=repmat(string(source.Value),height(tableOut),1);tableOut.Method=repmat(string(method),height(tableOut),1);
        tableOut.ReferenceFrame=repmat(frame,height(tableOut),1);tableOut.Scope=repmat(string(scope.Value),height(tableOut),1);
        tableOut.ChannelSeed=repmat(data.parameters.seed,height(tableOut),1);
        tableOut.ReferenceRange_m=repmat(r.range,height(tableOut),1);
        tableOut.ReferenceAngle_deg=repmat(r.angle,height(tableOut),1);
        tableOut.TotalSamples=repmat(fig.UserData.totalCount,height(tableOut),1);
        tableOut.FiniteSamples=repmat(fig.UserData.finiteCount,height(tableOut),1);
        tableOut.MatchedSamples=repmat(fig.UserData.matchCount,height(tableOut),1);
        % Coordinates are error transfers to the reference frame, not the
        % original per-frame positions when the source is a moving track.
        writetable(tableOut,fullfile(folder,file));
    end
end
