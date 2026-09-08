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
            if opts.Specified.MatFile
                height = 42;
            else
                height = 82;
            end
        end

        function [filePathEdit, browseButton, variableDropDown, sourceLayout] = ...
                addSourceSelector(mainGrid, opts, currentVariable)
            showFileControl = ~opts.Specified.MatFile;
            rowCount = 1 + double(showFileControl);
            selectorGrid = uigridlayout(mainGrid, [rowCount, 4]);
            selectorGrid.Layout.Row = 1;
            selectorGrid.ColumnWidth = {82, 410, 86, '1x'};
            selectorGrid.RowHeight = repmat({32}, 1, rowCount);
            selectorGrid.Padding = [4, 4, 4, 4];
            selectorGrid.ColumnSpacing = 8;
            selectorGrid.RowSpacing = 4;
        
            filePathEdit = gobjects(0);
            browseButton = gobjects(0);
            fileLabel = gobjects(0);
            fileHint = gobjects(0);
            variableRow = 1;
            if showFileControl
                fileLabel = uilabel(selectorGrid, 'Text', 'MAT 文件', ...
                    'FontWeight', 'bold', 'HorizontalAlignment', 'right');
                fileLabel.Layout.Row = 1;
                fileLabel.Layout.Column = 1;
        
                filePathEdit = uieditfield(selectorGrid, 'text', ...
                    'Value', opts.MatFile);
                filePathEdit.Layout.Row = 1;
                filePathEdit.Layout.Column = 2;
                filePathEdit.Tooltip = ...
                    '输入绝对路径，或相对于当前 MATLAB 工作目录的 MAT 文件路径。';
        
                browseButton = uibutton(selectorGrid, 'push', 'Text', '浏览…');
                browseButton.Layout.Row = 1;
                browseButton.Layout.Column = 3;
        
                fileHint = uilabel(selectorGrid, ...
                    'Text', '支持绝对路径或相对当前 MATLAB 工作目录的路径。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                fileHint.Layout.Row = 1;
                fileHint.Layout.Column = 4;
                variableRow = 2;
            end
        
            selectorLabel = uilabel(selectorGrid, 'Text', '目标变量', ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'right');
            selectorLabel.Layout.Row = variableRow;
            selectorLabel.Layout.Column = 1;
        
            itemValues = opts.AvailableVariables;
            items = itemValues;
            if isfield(opts, 'AvailableVariableInfo') && ...
                    numel(opts.AvailableVariableInfo) == numel(itemValues)
                items = arrayfun(@(item) sprintf('%s  [%s, %d-D]', ...
                    item.Path, strjoin(string(item.Size), 'x'), item.Dimension), ...
                    opts.AvailableVariableInfo, 'UniformOutput', false);
            end
            if isempty(currentVariable)
                if isempty(opts.MatFile)
                    placeholder = '请先指定 MAT 文件...';
                elseif isempty(itemValues)
                    placeholder = '未发现可绘制变量';
                else
                    placeholder = '请选择目标变量...';
                end
                items = [{placeholder}, items];
                itemValues = [{''}, itemValues];
            end
            variableDropDown = uidropdown(selectorGrid, ...
                'Items', items, 'ItemsData', itemValues, 'Value', currentVariable);
            variableDropDown.Layout.Row = variableRow;
            variableDropDown.Layout.Column = [2, 3];
            variableDropDown.Tooltip = opts.MatFile;
            if isempty(opts.MatFile) || isempty(opts.AvailableVariables)
                variableDropDown.Enable = 'off';
            end
        
            selectorHint = uilabel(selectorGrid, ...
                'Text', '选择或更换变量后会立即更新图像、范围和相关控制项。', ...
                'FontColor', [0.35, 0.35, 0.38]);
            selectorHint.Layout.Row = variableRow;
            selectorHint.Layout.Column = 4;
        
            sourceLayout = struct( ...
                'Grid', selectorGrid, ...
                'ShowFileControl', showFileControl, ...
                'FileLabel', fileLabel, ...
                'FilePathEdit', filePathEdit, ...
                'BrowseButton', browseButton, ...
                'FileHint', fileHint, ...
                'VariableLabel', selectorLabel, ...
                'VariableDropDown', variableDropDown, ...
                'VariableHint', selectorHint);
        end

        function sourceLayout = emptySourceLayout()
            sourceLayout = struct( ...
                'Grid', gobjects(0), ...
                'ShowFileControl', false, ...
                'FileLabel', gobjects(0), ...
                'FilePathEdit', gobjects(0), ...
                'BrowseButton', gobjects(0), ...
                'FileHint', gobjects(0), ...
                'VariableLabel', gobjects(0), ...
                'VariableDropDown', gobjects(0), ...
                'VariableHint', gobjects(0));
        end

        function shell = createViewerShell(fig, opts, currentVariable, panelTitle, ...
                controlPanelHeight, showColorbar)
            showSourceControl = isempty(currentVariable) || ...
                ~opts.Specified.MatFile || ~opts.Specified.Variable;
            rootPanel = uipanel(fig, 'BorderType', 'none', ...
                'BackgroundColor', fig.Color, ...
                'Position', [1, 1, fig.Position(3), fig.Position(4)]);
            if showSourceControl
                mainGrid = uigridlayout(rootPanel, [3, 1]);
                mainGrid.RowHeight = {matfield.Viewer.sourceSelectorHeight(opts), '1x', controlPanelHeight};
                plotRow = 2;
                controlRow = 3;
                [filePathEdit, browseButton, variableDropDown, sourceLayout] = ...
                    matfield.Viewer.addSourceSelector(mainGrid, opts, currentVariable);
            else
                mainGrid = uigridlayout(rootPanel, [2, 1]);
                mainGrid.RowHeight = {'1x', controlPanelHeight};
                plotRow = 1;
                controlRow = 2;
                filePathEdit = gobjects(0);
                browseButton = gobjects(0);
                variableDropDown = gobjects(0);
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
                'FilePathEdit', filePathEdit, ...
                'BrowseButton', browseButton, ...
                'VariableDropDown', variableDropDown, ...
                'HasColorbar', showColorbar);
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
            opts = state.Options;
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
                resolvedFile = matfield.Data.resolveMatFile(enteredPath);
                opts.MatFile = resolvedFile;
                opts.Variable = '';
                opts.PlotType = opts.RequestedPlotType;
                variableInfo = matfield.Data.listSelectableVariables(resolvedFile, opts);
                opts.AvailableVariables = {variableInfo.Path};
                opts.AvailableVariableInfo = variableInfo;
                matfield.SelectionView.createVariableSelectionFigure(opts, fig);
                fig.Pointer = 'arrow';
                drawnow
                if isempty(variableInfo)
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
                    if ~isempty(state.Options.MatFile)
                        source.Value = state.Options.MatFile;
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




        function onVariableChanged(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            previousVariable = state.Variable;
            selectedVariable = char(source.Value);
            if isempty(selectedVariable) || strcmp(selectedVariable, previousVariable)
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
                [fieldData, resolvedFile, fieldDimension] = ...
                    matfield.Data.loadTargetArray(opts.MatFile, selectedVariable);
                opts.MatFile = resolvedFile;
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
                uialert(fig, exception.message, '无法加载目标变量');
            end
        end

    end
end
