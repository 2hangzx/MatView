classdef SliceView
    %SLICEVIEW Create, update, and render the two-dimensional slice view.
    methods (Static)
        function fig = createSliceFigure(volumeData, opts, globalRange, existingFig)
            if nargin < 4
                existingFig = [];
            end
            dataSize = size(volumeData);
            fieldDimension = opts.FieldDimension;
            if fieldDimension == 3
                dimension = opts.Dimension;
                if isempty(opts.Index)
                    index = round((dataSize(dimension) + 1) / 2);
                else
                    index = double(opts.Index);
                end
            else
                dimension = [];
                index = [];
            end
            showModeControl = fieldDimension == 3 && ~opts.Specified.PlotType;
            showDimensionControl = fieldDimension == 3 && ~opts.Specified.Dimension;
            showIndexControl = fieldDimension == 3 && ~opts.Specified.Index;
            showColorControl = ~opts.Specified.ColorLimits;
            showSliceControlRow = showDimensionControl || showIndexControl || showColorControl;
            showPlaybackControl = showIndexControl;
        
            figName = sprintf('%s | slice', opts.Variable);
            fig = matfield.Viewer.prepareViewerFigure(existingFig, figName, [120, 80, 1120, 800], opts.Visible);
            controlPanelHeight = 100 + 34 * double(showModeControl) + ...
                42 * double(showSliceControlRow) + 42 * double(showColorControl) + ...
                36 * double(showPlaybackControl);
            shell = matfield.Viewer.createViewerShell(fig, opts, opts.Variable, '切片控制', ...
                controlPanelHeight, true);
            mainGrid = shell.MainGrid;
            ax = shell.Axes;
            cb = shell.Colorbar;
            controlPanel = shell.ControlPanel;
            filePathEdit = shell.FilePathEdit;
            browseButton = shell.BrowseButton;
            variableDropDown = shell.VariableDropDown;
            controlRow = shell.ControlPanelRow;
            controls = uigridlayout(controlPanel, [5, 14]);
            controls.RowHeight = {28, 34 * double(showModeControl), ...
                42 * double(showSliceControlRow), 42 * double(showColorControl), ...
                36 * double(showPlaybackControl)};
            controls.ColumnWidth = {62, 130, 42, '1x', '1x', '1x', ...
                72, 16, 72, 120, 34, 80, 34, 80};
            controls.Padding = [10, 14, 10, 8];
            controls.ColumnSpacing = 7;
            controls.RowSpacing = 6;
            controls.Scrollable = 'on';
        
            variableLabel = uilabel(controls, ...
                'Text', sprintf('变量：%s', opts.Variable), 'FontWeight', 'bold');
            variableLabel.Layout.Row = 1;
            variableLabel.Layout.Column = [1, 3];
            variableLabel.Tooltip = opts.MatFile;
        
            globalLabel = uilabel(controls, ...
                'Text', sprintf('全局 [min, max]：%s / %s', ...
                matfield.Graphics.formatNumber(globalRange(1)), matfield.Graphics.formatNumber(globalRange(2))));
            globalLabel.Layout.Row = 1;
            globalLabel.Layout.Column = [4, 7];
        
            sliceLabel = uilabel(controls, 'Text', '切片 [min, max]：-- / --');
            sliceLabel.Layout.Row = 1;
            sliceLabel.Layout.Column = [8, 14];
        
            modeText = gobjects(0);
            modeDropDown = gobjects(0);
            modeHint = gobjects(0);
            if showModeControl
                modeText = uilabel(controls, 'Text', '绘图模式');
                modeText.Layout.Row = 2;
                modeText.Layout.Column = 1;
                modeDropDown = uidropdown(controls, ...
                    'Items', {'Volume（三维等值面）', 'Slice（二维切片）'}, ...
                    'ItemsData', {'volume', 'slice'}, 'Value', 'slice');
                modeDropDown.Layout.Row = 2;
                modeDropDown.Layout.Column = [2, 4];
                modeHint = uilabel(controls, ...
                    'Text', '切换模式会立即复用当前数据重新绘图，无需重新加载 MAT 文件。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                modeHint.Layout.Row = 2;
                modeHint.Layout.Column = [5, 14];
            end
        
            dimText = gobjects(0);
            dimDropDown = gobjects(0);
            if showDimensionControl
                dimText = uilabel(controls, 'Text', '切片维度');
                dimText.Layout.Row = 3;
                dimText.Layout.Column = 1;
                dimDropDown = uidropdown(controls, ...
                    'Items', {'Dim 1', 'Dim 2', 'Dim 3'}, ...
                    'ItemsData', [1, 2, 3], 'Value', dimension);
                dimDropDown.Layout.Row = 3;
                dimDropDown.Layout.Column = 2;
            end
        
            indexText = gobjects(0);
            indexSlider = gobjects(0);
            indexEdit = gobjects(0);
            if showIndexControl
                indexText = uilabel(controls, 'Text', '索引');
                indexText.Layout.Row = 3;
                indexText.Layout.Column = 3;
                indexSlider = uislider(controls, ...
                    'Limits', [1, dataSize(dimension)], 'Value', index);
                indexSlider.Layout.Row = 3;
                indexSlider.Layout.Column = [4, 6];
                matfield.Graphics.configureSliderTicks(indexSlider, dataSize(dimension));
        
                indexEdit = uieditfield(controls, 'numeric', ...
                    'Limits', [1, dataSize(dimension)], 'RoundFractionalValues', 'on', ...
                    'ValueDisplayFormat', '%.0f', 'Value', index);
                indexEdit.Layout.Row = 3;
                indexEdit.Layout.Column = 7;
            end
        
            playbackText = gobjects(0);
            playButton = gobjects(0);
            intervalText = gobjects(0);
            playbackIntervalEdit = gobjects(0);
            playbackHint = gobjects(0);
            playbackTimer = [];
            if showPlaybackControl
                playbackText = uilabel(controls, 'Text', '自动播放');
                playbackText.Layout.Row = 5;
                playbackText.Layout.Column = 1;
                playButton = uibutton(controls, 'push', 'Text', '播放');
                playButton.Layout.Row = 5;
                playButton.Layout.Column = 2;
                intervalText = uilabel(controls, 'Text', '间隔(s)');
                intervalText.Layout.Row = 5;
                intervalText.Layout.Column = 3;
                playbackIntervalEdit = uieditfield(controls, 'numeric', ...
                    'Limits', [0.03, 10], 'ValueDisplayFormat', '%.2f', 'Value', 0.12);
                playbackIntervalEdit.Layout.Row = 5;
                playbackIntervalEdit.Layout.Column = 4;
                playbackHint = uilabel(controls, ...
                    'Text', '从当前索引向后播放，到末尾后从 1 循环。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                playbackHint.Layout.Row = 5;
                playbackHint.Layout.Column = [5, 14];
                playbackTimer = timer('ExecutionMode', 'fixedSpacing', ...
                    'BusyMode', 'drop', 'Period', playbackIntervalEdit.Value, ...
                    'TimerFcn', @(source, event) matfield.SliceView.advancePlayback(fig, source, event));
            end
        
            if isnumeric(opts.ColorLimits)
                colorMode = 'custom';
                customClim = matfield.Graphics.makeSafeLimits(opts.ColorLimits);
            else
                colorMode = opts.ColorLimits;
                customClim = matfield.Graphics.makeSafeLimits(globalRange);
            end
        
            colorText = gobjects(0);
            colorDropDown = gobjects(0);
            colorLowerText = gobjects(0);
            colorLowerEdit = gobjects(0);
            colorUpperText = gobjects(0);
            colorUpperEdit = gobjects(0);
            colorLowerSliderText = gobjects(0);
            colorLowerSlider = gobjects(0);
            colorUpperSliderText = gobjects(0);
            colorUpperSlider = gobjects(0);
            if showColorControl
                colorText = uilabel(controls, 'Text', '颜色栏范围');
                colorText.Layout.Row = 3;
                colorText.Layout.Column = 9;
                colorDropDown = uidropdown(controls, ...
                    'Items', {'全局范围', '当前切片', '指定范围'}, ...
                    'ItemsData', {'global', 'slice', 'custom'}, ...
                    'Value', colorMode);
                colorDropDown.Layout.Row = 3;
                colorDropDown.Layout.Column = 10;
        
                colorLowerText = uilabel(controls, 'Text', '下限');
                colorLowerText.Layout.Row = 3;
                colorLowerText.Layout.Column = 11;
                colorLowerEdit = uieditfield(controls, 'numeric', ...
                    'ValueDisplayFormat', '%.6g', 'Value', customClim(1));
                colorLowerEdit.Layout.Row = 3;
                colorLowerEdit.Layout.Column = 12;
        
                colorUpperText = uilabel(controls, 'Text', '上限');
                colorUpperText.Layout.Row = 3;
                colorUpperText.Layout.Column = 13;
                colorUpperEdit = uieditfield(controls, 'numeric', ...
                    'ValueDisplayFormat', '%.6g', 'Value', customClim(2));
                colorUpperEdit.Layout.Row = 3;
                colorUpperEdit.Layout.Column = 14;
        
                sliderLimits = matfield.Graphics.makeSafeLimits([min(globalRange(1), customClim(1)), ...
                    max(globalRange(2), customClim(2))]);
                colorLowerSliderText = uilabel(controls, 'Text', '下限粗调');
                colorLowerSliderText.Layout.Row = 4;
                colorLowerSliderText.Layout.Column = [1, 2];
                colorLowerSlider = uislider(controls, 'Limits', sliderLimits, ...
                    'Value', customClim(1));
                colorLowerSlider.Layout.Row = 4;
                colorLowerSlider.Layout.Column = [3, 7];
                matfield.Graphics.configureCompactValueSliderTicks(colorLowerSlider, sliderLimits);
        
                colorUpperSliderText = uilabel(controls, 'Text', '上限粗调');
                colorUpperSliderText.Layout.Row = 4;
                colorUpperSliderText.Layout.Column = [8, 9];
                colorUpperSlider = uislider(controls, 'Limits', sliderLimits, ...
                    'Value', customClim(2));
                colorUpperSlider.Layout.Row = 4;
                colorUpperSlider.Layout.Column = [10, 14];
                matfield.Graphics.configureCompactValueSliderTicks(colorUpperSlider, sliderLimits);
        
                customControlsEnabled = strcmp(colorMode, 'custom');
                matfield.Graphics.setControlEnabled(colorLowerText, customControlsEnabled);
                matfield.Graphics.setControlEnabled(colorLowerEdit, customControlsEnabled);
                matfield.Graphics.setControlEnabled(colorUpperText, customControlsEnabled);
                matfield.Graphics.setControlEnabled(colorUpperEdit, customControlsEnabled);
                matfield.Graphics.setControlEnabled(colorLowerSliderText, customControlsEnabled);
                matfield.Graphics.setControlEnabled(colorLowerSlider, customControlsEnabled);
                matfield.Graphics.setControlEnabled(colorUpperSliderText, customControlsEnabled);
                matfield.Graphics.setControlEnabled(colorUpperSlider, customControlsEnabled);
            end
        
            controlLayout = struct( ...
                'Kind', 'slice', ...
                'Grid', controls, ...
                'VariableLabel', variableLabel, ...
                'GlobalLabel', globalLabel, ...
                'SliceLabel', sliceLabel, ...
                'ModeText', modeText, ...
                'ModeDropDown', modeDropDown, ...
                'ModeHint', modeHint, ...
                'DimensionText', dimText, ...
                'DimensionDropDown', dimDropDown, ...
                'IndexText', indexText, ...
                'IndexSlider', indexSlider, ...
                'IndexEdit', indexEdit, ...
                'ColorText', colorText, ...
                'ColorDropDown', colorDropDown, ...
                'ColorLowerText', colorLowerText, ...
                'ColorLowerEdit', colorLowerEdit, ...
                'ColorUpperText', colorUpperText, ...
                'ColorUpperEdit', colorUpperEdit, ...
                'ColorLowerSliderText', colorLowerSliderText, ...
                'ColorLowerSlider', colorLowerSlider, ...
                'ColorUpperSliderText', colorUpperSliderText, ...
                'ColorUpperSlider', colorUpperSlider, ...
                'PlaybackText', playbackText, ...
                'PlayButton', playButton, ...
                'IntervalText', intervalText, ...
                'PlaybackIntervalEdit', playbackIntervalEdit, ...
                'PlaybackHint', playbackHint);
        
            state = struct( ...
                'Data', volumeData, ...
                'DataSize', dataSize, ...
                'FieldDimension', fieldDimension, ...
                'Variable', opts.Variable, ...
                'PlotMode', 'slice', ...
                'Options', opts, ...
                'Dimension', dimension, ...
                'Index', index, ...
                'GlobalRange', globalRange, ...
                'GlobalClim', matfield.Graphics.makeSafeLimits(globalRange), ...
                'CustomClim', customClim, ...
                'ColorMode', colorMode, ...
                'Axes', ax, ...
                'Colorbar', cb, ...
                'Image', gobjects(0), ...
                'FilePathEdit', filePathEdit, ...
                'BrowseButton', browseButton, ...
                'VariableDropDown', variableDropDown, ...
                'ModeDropDown', modeDropDown, ...
                'DimensionDropDown', dimDropDown, ...
                'IndexSlider', indexSlider, ...
                'IndexEdit', indexEdit, ...
                'ColorDropDown', colorDropDown, ...
                'ColorLowerText', colorLowerText, ...
                'ColorLowerEdit', colorLowerEdit, ...
                'ColorUpperText', colorUpperText, ...
                'ColorUpperEdit', colorUpperEdit, ...
                'ColorLowerSliderText', colorLowerSliderText, ...
                'ColorLowerSlider', colorLowerSlider, ...
                'ColorUpperSliderText', colorUpperSliderText, ...
                'ColorUpperSlider', colorUpperSlider, ...
                'SliceLabel', sliceLabel, ...
                'PlayButton', playButton, ...
                'PlaybackIntervalEdit', playbackIntervalEdit, ...
                'PlaybackTimer', playbackTimer, ...
                'LastSliceRenderClock', tic, ...
                'MainGrid', mainGrid, ...
                'ControlsGrid', controls, ...
                'ControlPanelRow', controlRow, ...
                'Layout', matfield.Layout.makeViewerLayout(shell, controlLayout, 'slice'));
            fig.UserData = state;
        
            if ~isempty(modeDropDown) && isgraphics(modeDropDown)
                modeDropDown.ValueChangedFcn = @(source, event) matfield.Viewer.onPlotModeChanged(fig, source, event);
            end
            if ~isempty(variableDropDown) && isgraphics(variableDropDown)
                variableDropDown.ValueChangedFcn = ...
                    @(source, event) matfield.Viewer.onVariableChanged(fig, source, event);
            end
            if ~isempty(filePathEdit) && isgraphics(filePathEdit)
                filePathEdit.ValueChangedFcn = ...
                    @(source, event) matfield.Viewer.onMatFilePathChanged(fig, source, event);
                browseButton.ButtonPushedFcn = ...
                    @(source, event) matfield.Viewer.browseForMatFile(fig, source, event);
            end
            if ~isempty(dimDropDown) && isgraphics(dimDropDown)
                dimDropDown.ValueChangedFcn = @(source, event) matfield.SliceView.onSliceDimensionChanged(fig, source, event);
            end
            if ~isempty(indexSlider) && isgraphics(indexSlider)
                indexSlider.ValueChangingFcn = @(source, event) matfield.SliceView.onSliceSliderMoving(fig, source, event);
                indexSlider.ValueChangedFcn = @(source, event) matfield.SliceView.onSliceSliderChanged(fig, source, event);
                indexEdit.ValueChangedFcn = @(source, event) matfield.SliceView.onSliceIndexEdited(fig, source, event);
            end
            if ~isempty(playButton) && isgraphics(playButton)
                playButton.ButtonPushedFcn = @(source, event) matfield.Playback.toggleViewerPlayback(fig, source, event);
                playbackIntervalEdit.ValueChangedFcn = ...
                    @(source, event) matfield.Playback.updateViewerPlaybackPeriod(fig, source, event);
            end
            if ~isempty(colorDropDown) && isgraphics(colorDropDown)
                colorDropDown.ValueChangedFcn = @(source, event) matfield.SliceView.onSliceColorModeChanged(fig, source, event);
                colorLowerEdit.ValueChangedFcn = ...
                    @(source, event) matfield.SliceView.onSliceColorLimitEdited(fig, source, event);
                colorUpperEdit.ValueChangedFcn = ...
                    @(source, event) matfield.SliceView.onSliceColorLimitEdited(fig, source, event);
                colorLowerSlider.ValueChangingFcn = @(source, event) ...
                    matfield.SliceView.onSliceColorLimitSlider(fig, 'lower', event.Value, false);
                colorLowerSlider.ValueChangedFcn = @(source, event) ...
                    matfield.SliceView.onSliceColorLimitSlider(fig, 'lower', source.Value, true);
                colorUpperSlider.ValueChangingFcn = @(source, event) ...
                    matfield.SliceView.onSliceColorLimitSlider(fig, 'upper', event.Value, false);
                colorUpperSlider.ValueChangedFcn = @(source, event) ...
                    matfield.SliceView.onSliceColorLimitSlider(fig, 'upper', source.Value, true);
            end
        
            matfield.SliceView.renderSlice(fig, index);
            matfield.Layout.enableResponsiveViewerLayout(fig);
        end

        function onSliceDimensionChanged(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            matfield.Playback.pauseViewerPlayback(fig);
            state = fig.UserData;
            oldLength = state.DataSize(state.Dimension);
            oldIndex = state.Index;
            newDimension = source.Value;
            newLength = state.DataSize(newDimension);
            if oldLength <= 1
                relativePosition = 0;
            else
                relativePosition = (oldIndex - 1) / (oldLength - 1);
            end
            newIndex = round(1 + relativePosition * (newLength - 1));
        
            state.Dimension = newDimension;
            if ~isempty(state.IndexSlider) && isgraphics(state.IndexSlider)
                state.IndexSlider.Limits = [1, newLength];
                matfield.Graphics.configureSliderTicks(state.IndexSlider, newLength);
                state.IndexEdit.Limits = [1, newLength];
            end
            fig.UserData = state;
            matfield.SliceView.renderSlice(fig, newIndex);
        end

        function onSliceSliderMoving(fig, ~, event)
            if isvalid(fig)
                matfield.Playback.pauseViewerPlayback(fig);
                state = fig.UserData;
                index = round(event.Value);
                if ~isempty(state.IndexEdit) && isgraphics(state.IndexEdit)
                    if state.IndexEdit.Value ~= index
                        state.IndexEdit.Value = index;
                    end
                end
                if index == state.Index
                    fig.UserData = state;
                    return
                end
                if toc(state.LastSliceRenderClock) < 0.04
                    fig.UserData = state;
                    return
                end
                state.LastSliceRenderClock = tic;
                fig.UserData = state;
                matfield.SliceView.renderSlice(fig, index, false);
            end
        end

        function onSliceSliderChanged(fig, source, ~)
            if isvalid(fig)
                matfield.Playback.pauseViewerPlayback(fig);
                matfield.SliceView.renderSlice(fig, round(source.Value), true);
            end
        end

        function onSliceIndexEdited(fig, source, ~)
            if isvalid(fig)
                matfield.Playback.pauseViewerPlayback(fig);
                matfield.SliceView.renderSlice(fig, round(source.Value), true);
            end
        end

        function onSliceColorModeChanged(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            state.ColorMode = source.Value;
            customEnabled = strcmp(state.ColorMode, 'custom');
            matfield.Graphics.setControlEnabled(state.ColorLowerText, customEnabled);
            matfield.Graphics.setControlEnabled(state.ColorLowerEdit, customEnabled);
            matfield.Graphics.setControlEnabled(state.ColorUpperText, customEnabled);
            matfield.Graphics.setControlEnabled(state.ColorUpperEdit, customEnabled);
            matfield.Graphics.setControlEnabled(state.ColorLowerSliderText, customEnabled);
            matfield.Graphics.setControlEnabled(state.ColorLowerSlider, customEnabled);
            matfield.Graphics.setControlEnabled(state.ColorUpperSliderText, customEnabled);
            matfield.Graphics.setControlEnabled(state.ColorUpperSlider, customEnabled);
            fig.UserData = state;
            matfield.SliceView.renderSlice(fig, state.Index);
        end

        function onSliceColorLimitEdited(fig, ~, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            requestedLimits = [state.ColorLowerEdit.Value, state.ColorUpperEdit.Value];
            if any(~isfinite(requestedLimits)) || requestedLimits(1) >= requestedLimits(2)
                state.ColorLowerEdit.Value = state.CustomClim(1);
                state.ColorUpperEdit.Value = state.CustomClim(2);
                matfield.Viewer.showViewerAlert(fig, '颜色栏范围下限必须是小于上限的有限数值。', ...
                    '颜色栏范围无效');
                return
            end
        
            state.CustomClim = double(requestedLimits);
            state.ColorMode = 'custom';
            state.ColorDropDown.Value = 'custom';
            state = matfield.SliceView.synchronizeSliceColorSliders(state);
            fig.UserData = state;
            matfield.SliceView.renderSlice(fig, state.Index);
        end

        function onSliceColorLimitSlider(fig, boundName, requestedValue, synchronizeSlider)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            limits = state.CustomClim;
            sliderSpan = diff(state.ColorLowerSlider.Limits);
            scale = max([abs(limits), abs(requestedValue), 1]);
            minimumGap = min(max(8 * eps(scale), sliderSpan * 1e-9), diff(limits));
            switch boundName
                case 'lower'
                    limits(1) = min(double(requestedValue), limits(2) - minimumGap);
                    state.ColorLowerEdit.Value = limits(1);
                    if synchronizeSlider
                        state.ColorLowerSlider.Value = limits(1);
                    end
                case 'upper'
                    limits(2) = max(double(requestedValue), limits(1) + minimumGap);
                    state.ColorUpperEdit.Value = limits(2);
                    if synchronizeSlider
                        state.ColorUpperSlider.Value = limits(2);
                    end
            end
        
            state.CustomClim = limits;
            state.ColorMode = 'custom';
            state.ColorDropDown.Value = 'custom';
            state.Axes.CLim = limits;
            if synchronizeSlider
                matfield.Graphics.refreshColorbarPresentation(state.Colorbar);
            else
                matfield.Graphics.restoreAutomaticColorbarTicks(state.Colorbar);
            end
            fig.UserData = state;
            drawnow limitrate nocallbacks
        end

        function state = synchronizeSliceColorSliders(state)
            sliderLimits = [min([state.ColorLowerSlider.Limits(1), ...
                state.GlobalRange(1), state.CustomClim(1)]), ...
                max([state.ColorUpperSlider.Limits(2), ...
                state.GlobalRange(2), state.CustomClim(2)])];
            sliderLimits = matfield.Graphics.makeSafeLimits(sliderLimits);
            state.ColorLowerSlider.Limits = sliderLimits;
            state.ColorUpperSlider.Limits = sliderLimits;
            state.ColorLowerSlider.Value = state.CustomClim(1);
            state.ColorUpperSlider.Value = state.CustomClim(2);
            matfield.Graphics.configureCompactValueSliderTicks(state.ColorLowerSlider, sliderLimits);
            matfield.Graphics.configureCompactValueSliderTicks(state.ColorUpperSlider, sliderLimits);
        end

        function renderSlice(fig, requestedIndex, synchronizeSlider)
            if ~isvalid(fig)
                return
            end
            if nargin < 3
                synchronizeSlider = true;
            end
            state = fig.UserData;
            if state.FieldDimension == 2
                dimension = [];
                index = [];
                plane = state.Data;
                remainingDims = [1, 2];
            else
                dimension = state.Dimension;
                index = min(max(round(requestedIndex), 1), state.DataSize(dimension));
                switch dimension
                    case 1
                        plane = squeeze(state.Data(index, :, :));
                    case 2
                        plane = squeeze(state.Data(:, index, :));
                    case 3
                        plane = state.Data(:, :, index);
                end
                remainingDims = setdiff(1:3, dimension, 'stable');
            end
        
            % Transpose so that the first remaining array dimension is horizontal
            % and the second is vertical, rather than silently assigning coordinate
            % meaning to matrix rows.
            displayPlane = plane.';
        
            if isempty(state.Image) || ~isgraphics(state.Image)
                state.Image = imagesc(state.Axes, displayPlane);
            else
                state.Image.CData = displayPlane;
                state.Image.XData = [1, size(displayPlane, 2)];
                state.Image.YData = [1, size(displayPlane, 1)];
            end
        
            finiteMask = isfinite(plane);
            if any(finiteMask, 'all')
                sliceRange = [min(plane(finiteMask)), max(plane(finiteMask))];
            else
                sliceRange = [NaN, NaN];
            end
        
            switch state.ColorMode
                case 'global'
                    state.Axes.CLim = state.GlobalClim;
                case 'slice'
                    if all(isfinite(sliceRange))
                        state.Axes.CLim = matfield.Graphics.makeSafeLimits(sliceRange);
                    else
                        state.Axes.CLim = state.GlobalClim;
                    end
                case 'custom'
                    state.Axes.CLim = state.CustomClim;
            end
        
            state.Index = index;
            if ~isempty(state.IndexSlider) && isgraphics(state.IndexSlider)
                state.IndexEdit.Value = index;
                if synchronizeSlider
                    state.IndexSlider.Value = index;
                end
            end
            state.SliceLabel.Text = sprintf('切片 [min, max]：%s / %s', ...
                matfield.Graphics.formatNumber(sliceRange(1)), matfield.Graphics.formatNumber(sliceRange(2)));
        
            if state.FieldDimension == 2
                title(state.Axes, sprintf('%s  |  2-D array', state.Variable), ...
                    'Interpreter', 'none');
            else
                title(state.Axes, sprintf('%s  |  Dim %d = %d', ...
                    state.Variable, dimension, index), 'Interpreter', 'none');
            end
            xlabel(state.Axes, sprintf('Dim %d index', remainingDims(1)));
            ylabel(state.Axes, sprintf('Dim %d index', remainingDims(2)));
            axis(state.Axes, 'xy');
            axis(state.Axes, 'image');
            state.Axes.XLim = [0.5, size(displayPlane, 2) + 0.5];
            state.Axes.YLim = [0.5, size(displayPlane, 1) + 0.5];
            if synchronizeSlider
                matfield.Graphics.refreshColorbarPresentation(state.Colorbar);
            else
                matfield.Graphics.restoreAutomaticColorbarTicks(state.Colorbar);
            end
            fig.UserData = state;
            drawnow limitrate nocallbacks
        end

        function advancePlayback(fig, ~, ~)
            %ADVANCEPLAYBACK Advance one slice frame and wrap at the axis end.
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            nextIndex = state.Index + 1;
            if nextIndex > state.DataSize(state.Dimension)
                nextIndex = 1;
            end
            matfield.SliceView.renderSlice(fig, nextIndex, true);
        end

    end
end
