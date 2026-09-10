classdef Viewer
    %VIEWER Coordinate figure lifecycle, source selection, and view switching.
    methods (Static)
        function fig = prepareViewerFigure(existingFig, figName, defaultPosition, visible)
            if isempty(existingFig)
                fig = uifigure('Name', figName, 'Position', defaultPosition, ...
                    'Color', [0.97, 0.97, 0.98], 'Visible', visible, ...
                    'ToolBar', 'figure', ...
                    'CloseRequestFcn', @(source, event) matfield.Playback.closeViewerFigure(source, event));
            else
                if ~isvalid(existingFig)
                    error('visualizeMatField:InvalidFigure', ...
                        'The viewer figure was closed before its mode could be changed.');
                end
                fig = existingFig;
                fig.SizeChangedFcn = [];
                fig.AutoResizeChildren = 'on';
                matfield.Playback.stopViewerPlayback(fig, true);
                delete(fig.Children);
                fig.Name = figName;
                fig.Color = [0.97, 0.97, 0.98];
                fig.ToolBar = 'figure';
            end
        end

        function height = sourceSelectorHeight(opts)
            rowCount = 1 + double(~opts.Specified.SourceType);
            switch opts.Source.Type
                case 'matfile'
                    rowCount = rowCount + double(~opts.Specified.MatFile);
                case {'workspace', 'memory'}
                    rowCount = rowCount + 1;
            end
            height = 8 + 36 * rowCount;
        end

        function sourceLayout = addSourceSelector(mainGrid, opts, currentVariable)
            showSourceTypeControl = ~opts.Specified.SourceType;
            showFileControl = ~opts.Specified.MatFile;
            showFileControl = showFileControl && strcmp(opts.Source.Type, 'matfile');
            showWorkspaceControl = strcmp(opts.Source.Type, 'workspace');
            showMemoryControl = strcmp(opts.Source.Type, 'memory');
            rowCount = 1 + double(showSourceTypeControl) + ...
                double(showFileControl || showWorkspaceControl || showMemoryControl);
            selectorGrid = uigridlayout(mainGrid, [rowCount, 4]);
            selectorGrid.Layout.Row = 1;
            selectorGrid.ColumnWidth = {82, 410, 86, '1x'};
            selectorGrid.RowHeight = repmat({32}, 1, rowCount);
            selectorGrid.Padding = [4, 4, 4, 4];
            selectorGrid.ColumnSpacing = 8;
            selectorGrid.RowSpacing = 4;

            groups = {};
            sourceTypeLabel = gobjects(0);
            sourceTypeDropDown = gobjects(0);
            sourceTypeHint = gobjects(0);
            if showSourceTypeControl
                sourceTypeLabel = uilabel(selectorGrid, 'Text', '数据源类型', ...
                    'FontWeight', 'bold', 'HorizontalAlignment', 'right');
                sourceTypeDropDown = uidropdown(selectorGrid, ...
                    'Items', {'MAT 文件', 'MATLAB 工作区'}, ...
                    'ItemsData', {'matfile', 'workspace'}, ...
                    'Value', opts.Source.Type);
                sourceTypeHint = uilabel(selectorGrid, ...
                    'Text', '选择数据来源；切换后旧图像和旧播放状态会被清空。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                groups{end + 1} = matfield.Viewer.makeSourceGroup( ...
                    sourceTypeLabel, sourceTypeDropDown, gobjects(0), ...
                    sourceTypeHint);
            end

            filePathEdit = gobjects(0);
            browseButton = gobjects(0);
            fileLabel = gobjects(0);
            fileHint = gobjects(0);
            if showFileControl
                fileLabel = uilabel(selectorGrid, 'Text', 'MAT 文件', ...
                    'FontWeight', 'bold', 'HorizontalAlignment', 'right');
                filePathEdit = uieditfield(selectorGrid, 'text', ...
                    'Value', opts.MatFile);
                filePathEdit.Tooltip = ...
                    '输入绝对路径，或相对于当前 MATLAB 工作目录的 MAT 文件路径。';
                browseButton = uibutton(selectorGrid, 'push', 'Text', '浏览…');
                fileHint = uilabel(selectorGrid, ...
                    'Text', '支持绝对路径或相对当前 MATLAB 工作目录的路径。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                groups{end + 1} = matfield.Viewer.makeSourceGroup( ...
                    fileLabel, filePathEdit, browseButton, fileHint);
            end

            workspaceLabel = gobjects(0);
            workspaceValue = gobjects(0);
            workspaceRefreshButton = gobjects(0);
            workspaceHint = gobjects(0);
            if showWorkspaceControl
                workspaceLabel = uilabel(selectorGrid, 'Text', '工作区', ...
                    'FontWeight', 'bold', 'HorizontalAlignment', 'right');
                workspaceValue = uilabel(selectorGrid, 'Text', 'Base Workspace');
                workspaceRefreshButton = uibutton(selectorGrid, 'push', ...
                    'Text', '刷新');
                workspaceHint = uilabel(selectorGrid, ...
                    'Text', '显式刷新变量列表；当前图像使用最近一次读取的快照。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                groups{end + 1} = matfield.Viewer.makeSourceGroup( ...
                    workspaceLabel, workspaceValue, workspaceRefreshButton, ...
                    workspaceHint);
            end

            memoryLabel = gobjects(0);
            memoryValue = gobjects(0);
            memoryHint = gobjects(0);
            if showMemoryControl
                memoryLabel = uilabel(selectorGrid, 'Text', '内存变量', ...
                    'FontWeight', 'bold', 'HorizontalAlignment', 'right');
                memoryValue = uilabel(selectorGrid, ...
                    'Text', opts.Source.RootName);
                memoryHint = uilabel(selectorGrid, ...
                    'Text', '调用时传入的快照；函数局部变量不依赖后续 caller 回调。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                groups{end + 1} = matfield.Viewer.makeSourceGroup( ...
                    memoryLabel, memoryValue, gobjects(0), memoryHint);
            end

            selectorLabel = uilabel(selectorGrid, 'Text', '目标变量', ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'right');
            itemValues = opts.AvailableVariables;
            items = itemValues;
            if isfield(opts, 'AvailableVariableInfo') && ...
                    numel(opts.AvailableVariableInfo) == numel(itemValues)
                items = arrayfun(@(item) sprintf('%s  [%s, %d-D]', ...
                    item.Path, strjoin(string(item.Size), 'x'), item.Dimension), ...
                    opts.AvailableVariableInfo, 'UniformOutput', false);
            end
            if ~isempty(currentVariable) && ...
                    ~any(strcmp(itemValues, currentVariable))
                items = [{currentVariable}, items];
                itemValues = [{currentVariable}, itemValues];
            end
            if isempty(currentVariable)
                if ~matfield.Data.isReady(opts.Source)
                    placeholder = '请先指定 MAT 文件...';
                elseif isempty(itemValues)
                    if strcmp(opts.Source.Type, 'workspace')
                        placeholder = '未发现可绘制变量，请刷新...';
                    else
                        placeholder = '未发现可绘制变量';
                    end
                else
                    placeholder = '请选择目标变量...';
                end
                items = [{placeholder}, items];
                itemValues = [{''}, itemValues];
            end
            variableDropDown = uidropdown(selectorGrid, ...
                'Items', items, 'ItemsData', itemValues, 'Value', currentVariable);
            variableDropDown.Tooltip = matfield.Data.tooltip(opts.Source);
            if ~matfield.Data.isReady(opts.Source) || isempty(opts.AvailableVariables)
                variableDropDown.Enable = 'off';
            end
            selectorHint = uilabel(selectorGrid, ...
                'Text', '选择或更换变量后会立即更新图像、范围和相关控制项。', ...
                'FontColor', [0.35, 0.35, 0.38]);
            groups{end + 1} = matfield.Viewer.makeSourceGroup( ...
                selectorLabel, variableDropDown, gobjects(0), selectorHint);

            sourceLayout = struct( ...
                'Grid', selectorGrid, ...
                'Groups', {groups}, ...
                'ShowSourceTypeControl', showSourceTypeControl, ...
                'ShowFileControl', showFileControl, ...
                'ShowWorkspaceControl', showWorkspaceControl, ...
                'ShowMemoryControl', showMemoryControl, ...
                'SourceTypeLabel', sourceTypeLabel, ...
                'SourceTypeDropDown', sourceTypeDropDown, ...
                'SourceTypeHint', sourceTypeHint, ...
                'FileLabel', fileLabel, ...
                'FilePathEdit', filePathEdit, ...
                'BrowseButton', browseButton, ...
                'FileHint', fileHint, ...
                'WorkspaceLabel', workspaceLabel, ...
                'WorkspaceValue', workspaceValue, ...
                'WorkspaceRefreshButton', workspaceRefreshButton, ...
                'WorkspaceHint', workspaceHint, ...
                'MemoryLabel', memoryLabel, ...
                'MemoryValue', memoryValue, ...
                'MemoryHint', memoryHint, ...
                'VariableLabel', selectorLabel, ...
                'VariableDropDown', variableDropDown, ...
                'VariableHint', selectorHint);
        end

        function group = makeSourceGroup(label, primary, action, hint)
            group = struct('Label', label, 'Primary', primary, ...
                'Action', action, 'Hint', hint);
        end

        function sourceLayout = emptySourceLayout()
            sourceLayout = struct( ...
                'Grid', gobjects(0), ...
                'Groups', {{}}, ...
                'ShowSourceTypeControl', false, ...
                'ShowFileControl', false, ...
                'ShowWorkspaceControl', false, ...
                'ShowMemoryControl', false, ...
                'SourceTypeLabel', gobjects(0), ...
                'SourceTypeDropDown', gobjects(0), ...
                'SourceTypeHint', gobjects(0), ...
                'FileLabel', gobjects(0), ...
                'FilePathEdit', gobjects(0), ...
                'BrowseButton', gobjects(0), ...
                'FileHint', gobjects(0), ...
                'WorkspaceLabel', gobjects(0), ...
                'WorkspaceValue', gobjects(0), ...
                'WorkspaceRefreshButton', gobjects(0), ...
                'WorkspaceHint', gobjects(0), ...
                'MemoryLabel', gobjects(0), ...
                'MemoryValue', gobjects(0), ...
                'MemoryHint', gobjects(0), ...
                'VariableLabel', gobjects(0), ...
                'VariableDropDown', gobjects(0), ...
                'VariableHint', gobjects(0));
        end

        function shell = createViewerShell(fig, opts, currentVariable, panelTitle, ...
                controlPanelHeight, showColorbar)
            showSourceControl = strcmp(opts.Source.Type, 'workspace') || ...
                isempty(currentVariable) || ~opts.Specified.SourceType || ...
                ~opts.Specified.Variable;
            rootPanel = uipanel(fig, 'BorderType', 'none', ...
                'BackgroundColor', fig.Color, ...
                'Position', [1, 1, fig.Position(3), fig.Position(4)]);
            if showSourceControl
                mainGrid = uigridlayout(rootPanel, [3, 1]);
                mainGrid.RowHeight = {matfield.Viewer.sourceSelectorHeight(opts), '1x', controlPanelHeight};
                plotRow = 2;
                controlRow = 3;
                sourceLayout = matfield.Viewer.addSourceSelector( ...
                    mainGrid, opts, currentVariable);
            else
                mainGrid = uigridlayout(rootPanel, [2, 1]);
                mainGrid.RowHeight = {'1x', controlPanelHeight};
                plotRow = 1;
                controlRow = 2;
                sourceLayout = matfield.Viewer.emptySourceLayout();
            end
            mainGrid.Padding = [18, 18, 18, 18];
            mainGrid.RowSpacing = 8;
        
            plotGrid = uigridlayout(mainGrid, [1, 1]);
            plotGrid.Layout.Row = plotRow;
            plotGrid.RowSpacing = 0;
            plotGrid.ColumnSpacing = 0;
            if showColorbar
                plotGrid.Padding = [0, 0, 132, 26];
            else
                plotGrid.Padding = [0, 0, 0, 0];
            end
            ax = uiaxes(plotGrid);
            ax.Box = 'on';
            ax.FontName = 'Consolas';
            ax.FontSize = 12;
            ax.Toolbar.Visible = 'on';
            colormap(ax, opts.Colormap);
        
            cb = gobjects(0);
            if showColorbar
                cb = colorbar(ax);
                cb.Label.String = 'Value';
            end
        
            controlPanel = uipanel(mainGrid, 'Title', panelTitle, ...
                'FontWeight', 'bold', 'BackgroundColor', [0.98, 0.98, 0.99], ...
                'Scrollable', 'off');
            controlPanel.Layout.Row = controlRow;
        
            shell = struct( ...
                'RootPanel', rootPanel, ...
                'MainGrid', mainGrid, ...
                'PlotGrid', plotGrid, ...
                'Axes', ax, ...
                'Colorbar', cb, ...
                'ControlPanel', controlPanel, ...
                'ControlPanelRow', controlRow, ...
                'SourceLayout', sourceLayout, ...
                'SourceTypeDropDown', sourceLayout.SourceTypeDropDown, ...
                'FilePathEdit', sourceLayout.FilePathEdit, ...
                'BrowseButton', sourceLayout.BrowseButton, ...
                'WorkspaceRefreshButton', sourceLayout.WorkspaceRefreshButton, ...
                'VariableDropDown', sourceLayout.VariableDropDown, ...
                'HasColorbar', showColorbar);
        end

        function wireSourceCallbacks(fig, shell)
            if matfield.Graphics.hasGraphics(shell.SourceTypeDropDown)
                shell.SourceTypeDropDown.ValueChangedFcn = ...
                    @(source, event) matfield.Viewer.onSourceTypeChanged( ...
                    fig, source, event);
            end
            if matfield.Graphics.hasGraphics(shell.FilePathEdit)
                shell.FilePathEdit.ValueChangedFcn = ...
                    @(source, event) matfield.Viewer.onMatFilePathChanged( ...
                    fig, source, event);
                shell.BrowseButton.ButtonPushedFcn = ...
                    @(source, event) matfield.Viewer.browseForMatFile( ...
                    fig, source, event);
            end
            if matfield.Graphics.hasGraphics(shell.WorkspaceRefreshButton)
                shell.WorkspaceRefreshButton.ButtonPushedFcn = ...
                    @(source, event) matfield.Viewer.refreshWorkspace( ...
                    fig, source, event);
            end
            if matfield.Graphics.hasGraphics(shell.VariableDropDown)
                shell.VariableDropDown.ValueChangedFcn = ...
                    @(source, event) matfield.Viewer.onVariableChanged( ...
                    fig, source, event);
            end
        end

        function opts = updateAvailableTargets(opts)
            variableInfo = matfield.Data.listTargets(opts.Source, opts);
            opts.AvailableVariables = {variableInfo.Path};
            opts.AvailableVariableInfo = variableInfo;
        end

        function opts = resetOptionsForNewSource(opts)
            defaults = opts.SourceChangeDefaults;
            fields = fieldnames(defaults);
            for fieldIndex = 1:numel(fields)
                field = fields{fieldIndex};
                opts.(field) = defaults.(field);
            end
            runtimeFields = {'RuntimeIsoSelectionMode', 'RuntimeExactIsoValue'};
            for fieldIndex = 1:numel(runtimeFields)
                field = runtimeFields{fieldIndex};
                if isfield(opts, field)
                    opts = rmfield(opts, field);
                end
            end
        end

        function onSourceTypeChanged(fig, control, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            newSourceType = char(control.Value);
            if strcmp(newSourceType, state.Options.Source.Type)
                return
            end

            opts = matfield.Viewer.resetOptionsForNewSource(state.Options);
            opts.SourceType = newSourceType;
            opts.RequestedSourceType = newSourceType;
            opts.Source = matfield.Data.makeSource(newSourceType);
            opts.MatFile = '';
            opts.Variable = '';
            opts.Specified.MatFile = false;
            opts.Specified.Variable = false;
            if matfield.Data.isReady(opts.Source)
                opts = matfield.Viewer.updateAvailableTargets(opts);
            else
                opts.AvailableVariables = {};
                opts.AvailableVariableInfo = matfield.Data.emptyVariableInfo();
            end
            matfield.SelectionView.createVariableSelectionFigure(opts, fig);
        end

        function refreshWorkspace(fig, control, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            if ~strcmp(state.Options.Source.Type, 'workspace')
                return
            end

            control.Enable = 'off';
            fig.Pointer = 'watch';
            drawnow
            try
                selectedVariable = state.Variable;
                opts = state.Options;
                opts.Source = state.Source;
                opts = matfield.Viewer.updateAvailableTargets(opts);
                if ~isempty(selectedVariable) && ...
                        any(strcmp(opts.AvailableVariables, selectedVariable))
                    state.Options = opts;
                    fig.UserData = state;
                    state.VariableDropDown.Items = arrayfun(@(item) ...
                        sprintf('%s  [%s, %d-D]', item.Path, ...
                        strjoin(string(item.Size), 'x'), item.Dimension), ...
                        opts.AvailableVariableInfo, 'UniformOutput', false);
                    state.VariableDropDown.ItemsData = opts.AvailableVariables;
                    state.VariableDropDown.Value = selectedVariable;
                    matfield.Viewer.onVariableChanged( ...
                        fig, state.VariableDropDown, [], true);
                else
                    opts.Variable = '';
                    opts.PlotType = opts.RequestedPlotType;
                    opts.Specified.Variable = false;
                    matfield.SelectionView.createVariableSelectionFigure(opts, fig);
                end
                if isvalid(fig)
                    fig.Pointer = 'arrow';
                end
            catch exception
                if isvalid(fig)
                    fig.Pointer = 'arrow';
                end
                if isgraphics(control)
                    control.Enable = 'on';
                end
                matfield.Viewer.showViewerAlert( ...
                    fig, exception.message, '无法刷新工作区');
            end
        end

        function browseForMatFile(fig, ~, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            initialFolder = pwd;
            currentPath = state.FilePathEdit.Value;
            if ~isempty(strtrim(currentPath))
                candidate = currentPath;
                if ~isfile(candidate)
                    candidate = fullfile(pwd, candidate);
                end
                candidateFolder = fileparts(candidate);
                if isfolder(candidateFolder)
                    initialFolder = candidateFolder;
                end
            end
        
            [fileName, folderName] = uigetfile( ...
                {'*.mat', 'MAT 文件 (*.mat)'}, '选择 MAT 文件', ...
                fullfile(initialFolder, '*.mat'), 'MultiSelect', 'off');
            if isequal(fileName, 0)
                return
            end
            state = fig.UserData;
            state.FilePathEdit.Value = fullfile(folderName, fileName);
            fig.UserData = state;
            matfield.Viewer.onMatFilePathChanged(fig, state.FilePathEdit, []);
        end

        function onMatFilePathChanged(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            opts = matfield.Viewer.resetOptionsForNewSource(state.Options);
            enteredPath = strtrim(source.Value);
            if isempty(enteredPath)
                matfield.Viewer.showViewerAlert(fig, '请输入 MAT 文件路径，或使用“浏览…”按钮选择文件。', ...
                    '尚未指定 MAT 文件');
                return
            end
        
            source.Enable = 'off';
            fig.Pointer = 'watch';
            drawnow
            try
                opts.Source = matfield.Data.makeSource('matfile', enteredPath);
                opts.Source = matfield.Data.resolve(opts.Source);
                opts.MatFile = opts.Source.Location;
                opts.Variable = '';
                opts = matfield.Viewer.updateAvailableTargets(opts);
                matfield.SelectionView.createVariableSelectionFigure(opts, fig);
                fig.Pointer = 'arrow';
                drawnow
                if isempty(opts.AvailableVariables)
                    matfield.Viewer.showViewerAlert(fig, ...
                        '该 MAT 文件中没有符合当前绘图参数的实数数值二维/三维数组。', ...
                        '未发现可绘制变量');
                end
            catch exception
                if isvalid(fig)
                    fig.Pointer = 'arrow';
                end
                if isgraphics(source)
                    source.Enable = 'on';
                    if strcmp(state.Options.Source.Type, 'matfile') && ...
                            ~isempty(state.Options.Source.Location)
                        source.Value = state.Options.Source.Location;
                    end
                end
                matfield.Viewer.showViewerAlert(fig, exception.message, '无法打开 MAT 文件');
            end
        end

        function showViewerAlert(fig, message, titleText)
            if isvalid(fig) && strcmp(fig.Visible, 'on')
                uialert(fig, message, titleText);
            end
        end

        function onPlotModeChanged(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            newMode = char(source.Value);
            state = fig.UserData;
            if strcmp(newMode, state.PlotMode)
                return
            end
        
            % Preserve the latest controls from each mode. Switching modes rebuilds
            % only the UI and plot; state.Data is reused and the MAT file is not read
            % again.
            opts = state.Options;
            switch state.PlotMode
                case 'slice'
                    opts.Dimension = state.Dimension;
                    opts.Index = state.Index;
                    if strcmp(state.ColorMode, 'custom')
                        opts.ColorLimits = state.CustomClim;
                    else
                        opts.ColorLimits = state.ColorMode;
                    end
                case 'volume'
                    opts.NumIsosurfaces = state.NumIsosurfaces;
                    if ~isempty(state.CountSpinner) && isgraphics(state.CountSpinner)
                        opts.NumIsosurfaces = round(state.CountSpinner.Value);
                    end
                    opts.IsoRange = state.IsoRange;
                    if ~isempty(state.LowerEdit) && isgraphics(state.LowerEdit)
                        lowerFraction = state.LowerEdit.Value / 100;
                        upperFraction = state.UpperEdit.Value / 100;
                        if lowerFraction < upperFraction
                            opts.IsoRange = [lowerFraction, upperFraction];
                        end
                    end
                    opts.IsoValues = state.IsoValues;
                    opts.RuntimeIsoSelectionMode = state.IsoSelectionMode;
                    opts.RuntimeExactIsoValue = state.ExactIsoValue;
                    opts.SurfaceAlpha = state.SurfaceAlpha;
                    if ~isempty(state.AlphaSlider) && isgraphics(state.AlphaSlider)
                        opts.SurfaceAlpha = state.AlphaSlider.Value;
                    end
            end
            opts.PlotType = newMode;
        
            volumeData = state.Data;
            globalRange = state.GlobalRange;
            fig.Pointer = 'watch';
            drawnow
            try
                switch newMode
                    case 'slice'
                        matfield.SliceView.createSliceFigure(volumeData, opts, globalRange, fig);
                    case 'volume'
                        matfield.VolumeView.createVolumeFigure(volumeData, opts, globalRange, fig);
                end
                fig.Pointer = 'arrow';
                drawnow
            catch exception
                if isvalid(fig)
                    fig.Pointer = 'arrow';
                end
                rethrow(exception)
            end
        end




        function onVariableChanged(fig, source, ~, forceReload)
            if nargin < 4
                forceReload = false;
            end
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            previousVariable = state.Variable;
            selectedVariable = char(source.Value);
            if isempty(selectedVariable) || ...
                    (strcmp(selectedVariable, previousVariable) && ~forceReload)
                return
            end
        
            opts = state.Options;
            opts.PlotType = state.PlotMode;
            oldGlobalRange = [];
            oldDataSize = [];
            oldFieldDimension = 0;
            oldDimension = [];
            oldIndex = [];
            if ~isempty(previousVariable)
                oldGlobalRange = state.GlobalRange;
                oldFieldDimension = state.FieldDimension;
                switch state.PlotMode
                    case 'slice'
                        opts.Dimension = state.Dimension;
                        opts.Index = state.Index;
                        oldDataSize = state.DataSize;
                        oldDimension = state.Dimension;
                        oldIndex = state.Index;
                        if strcmp(state.ColorMode, 'custom')
                            opts.ColorLimits = state.CustomClim;
                        else
                            opts.ColorLimits = state.ColorMode;
                        end
                    case 'volume'
                        opts.NumIsosurfaces = state.NumIsosurfaces;
                        if ~isempty(state.CountSpinner) && isgraphics(state.CountSpinner)
                            opts.NumIsosurfaces = round(state.CountSpinner.Value);
                        end
                        opts.IsoRange = state.IsoRange;
                        if ~isempty(state.LowerEdit) && isgraphics(state.LowerEdit) && ...
                                state.LowerEdit.Value < state.UpperEdit.Value
                            opts.IsoRange = [state.LowerEdit.Value, state.UpperEdit.Value] / 100;
                        end
                        opts.IsoValues = state.IsoValues;
                        opts.RuntimeIsoSelectionMode = state.IsoSelectionMode;
                        opts.RuntimeExactIsoValue = state.ExactIsoValue;
                        opts.SurfaceAlpha = state.SurfaceAlpha;
                        if ~isempty(state.AlphaSlider) && isgraphics(state.AlphaSlider)
                            opts.SurfaceAlpha = state.AlphaSlider.Value;
                        end
                end
            end
        
            opts.Variable = selectedVariable;
            source.Enable = 'off';
            fig.Pointer = 'watch';
            drawnow
            try
                [fieldData, opts.Source, fieldDimension, canonicalPath] = ...
                    matfield.Data.loadTarget(opts.Source, selectedVariable);
                opts.Variable = canonicalPath;
                if strcmp(opts.Source.Type, 'matfile')
                    opts.MatFile = opts.Source.Location;
                else
                    opts.MatFile = '';
                end
                opts.FieldDimension = fieldDimension;
                opts.PlotType = matfield.Data.resolvePlotTypeForField(opts, fieldDimension);
                if fieldDimension == 3
                    opts.Dimension = matfield.Input.normalizeDimension(opts.Dimension);
                end
                globalRange = matfield.Data.validateLoadedArray(fieldData, opts);
        
                if strcmp(opts.PlotType, 'slice') && fieldDimension == 3
                    if opts.Specified.Index
                        matfield.Input.validateInitialIndex(opts.Index, opts.Dimension, size(fieldData));
                    elseif oldFieldDimension == 3 && ~isempty(oldDataSize)
                        oldLength = oldDataSize(oldDimension);
                        newLength = size(fieldData, opts.Dimension);
                        if oldLength <= 1
                            relativePosition = 0;
                        else
                            relativePosition = (oldIndex - 1) / (oldLength - 1);
                        end
                        opts.Index = round(1 + relativePosition * (newLength - 1));
                    else
                        opts.Index = [];
                    end
                elseif strcmp(opts.PlotType, 'volume') && ...
                        isfield(opts, 'RuntimeIsoSelectionMode') && ...
                        strcmp(opts.RuntimeIsoSelectionMode, 'single') && ...
                        ~isempty(oldGlobalRange)
                    oldSpan = diff(oldGlobalRange);
                    if oldSpan > 0
                        relativeValue = (opts.RuntimeExactIsoValue - oldGlobalRange(1)) / oldSpan;
                        relativeValue = max(0, min(1, relativeValue));
                        opts.RuntimeExactIsoValue = globalRange(1) + ...
                            relativeValue * diff(globalRange);
                    else
                        opts.RuntimeExactIsoValue = mean(globalRange);
                    end
                end
        
                switch opts.PlotType
                    case 'slice'
                        matfield.SliceView.createSliceFigure(fieldData, opts, globalRange, fig);
                    case 'volume'
                        matfield.VolumeView.createVolumeFigure(fieldData, opts, globalRange, fig);
                end
                fig.Pointer = 'arrow';
                drawnow
            catch exception
                if isvalid(fig)
                    fig.Pointer = 'arrow';
                end
                if isgraphics(source)
                    source.Enable = 'on';
                    source.Value = previousVariable;
                end
                matfield.Viewer.showViewerAlert( ...
                    fig, exception.message, '无法加载目标变量');
            end
        end

    end
end
