classdef VolumeView
    %VOLUMEVIEW Create, update, and render the three-dimensional isosurface view.
    methods (Static)
        function fig = createVolumeFigure(volumeData, opts, globalRange, existingFig)
            if nargin < 4
                existingFig = [];
            end
            if opts.FieldDimension ~= 3
                error('visualizeMatField:VolumeRequires3D', ...
                    'Volume mode requires a real numeric 3-D array.');
            end
            showModeControl = ~opts.Specified.PlotType;
            useExactIsoValues = opts.Specified.IsoValues;
            automaticModeSpecified = opts.Specified.NumIsosurfaces || opts.Specified.IsoRange;
            showIsoModeControl = ~useExactIsoValues && ~automaticModeSpecified;
            showCountControl = ~useExactIsoValues && ~opts.Specified.NumIsosurfaces;
            showRangeControl = ~useExactIsoValues && ~opts.Specified.IsoRange;
            showAlphaControl = ~opts.Specified.SurfaceAlpha;
            showExactValueControl = showIsoModeControl;
            showVolumeControlRow = showCountControl || showRangeControl || ...
                showExactValueControl || showAlphaControl;
        
            isoSelectionMode = 'automatic';
            if useExactIsoValues
                isoSelectionMode = 'fixed';
            elseif showIsoModeControl && isfield(opts, 'RuntimeIsoSelectionMode')
                isoSelectionMode = opts.RuntimeIsoSelectionMode;
            end
            exactIsoValue = mean(globalRange);
            if isfield(opts, 'RuntimeExactIsoValue')
                exactIsoValue = opts.RuntimeExactIsoValue;
            end
            exactValueLimits = matfield.Graphics.makeSafeLimits(globalRange);
            exactIsoValue = max(exactValueLimits(1), min(exactValueLimits(2), exactIsoValue));
            showExactPlaybackInitially = showExactValueControl && strcmp(isoSelectionMode, 'single');
            baseControlPanelHeight = 100 + 34 * double(showModeControl) + ...
                36 * double(showIsoModeControl) + 46 * double(showVolumeControlRow);
        
            figName = sprintf('%s | 3-D isosurfaces', opts.Variable);
            fig = matfield.Viewer.prepareViewerFigure(existingFig, figName, [120, 70, 1180, 830], opts.Visible);
            controlPanelHeight = baseControlPanelHeight + ...
                36 * double(showExactPlaybackInitially);
            shell = matfield.Viewer.createViewerShell(fig, opts, opts.Variable, '三维等值面控制', ...
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
                36 * double(showIsoModeControl), 46 * double(showVolumeControlRow), ...
                36 * double(showExactPlaybackInitially)};
            controls.ColumnWidth = {82, 62, 76, 62, 76, 62, 55, ...
                '1x', '1x', '1x', 55, 62, 62, 72};
            controls.Padding = [10, 14, 10, 8];
            controls.ColumnSpacing = 7;
            controls.RowSpacing = 6;
            controls.Scrollable = 'on';
        
            variableLabel = uilabel(controls, ...
                'Text', sprintf('变量：%s', opts.Variable), 'FontWeight', 'bold');
            variableLabel.Layout.Row = 1;
            variableLabel.Layout.Column = [1, 5];
            variableLabel.Tooltip = opts.MatFile;
        
            globalLabel = uilabel(controls, ...
                'Text', sprintf('全局 [min, max]：%s / %s', ...
                matfield.Graphics.formatNumber(globalRange(1)), matfield.Graphics.formatNumber(globalRange(2))));
            globalLabel.Layout.Row = 1;
            globalLabel.Layout.Column = [6, 9];
        
            sampleIndices = cell(1, 3);
            for dim = 1:3
                sampleIndices{dim} = matfield.Graphics.makeSampleIndices(size(volumeData, dim), opts.MaxRenderSize);
            end
            sampledSize = cellfun(@numel, sampleIndices);
            samplingLabel = uilabel(controls, ...
                'Text', sprintf('绘制采样：%s（统计使用完整数据）', mat2str(sampledSize)));
            samplingLabel.Layout.Row = 1;
            samplingLabel.Layout.Column = [10, 14];
        
            modeText = gobjects(0);
            modeDropDown = gobjects(0);
            modeHint = gobjects(0);
            if showModeControl
                modeText = uilabel(controls, 'Text', '绘图模式');
                modeText.Layout.Row = 2;
                modeText.Layout.Column = 1;
                modeDropDown = uidropdown(controls, ...
                    'Items', {'Volume（三维等值面）', 'Slice（二维切片）'}, ...
                    'ItemsData', {'volume', 'slice'}, 'Value', 'volume');
                modeDropDown.Layout.Row = 2;
                modeDropDown.Layout.Column = [2, 4];
                modeHint = uilabel(controls, ...
                    'Text', '切换模式会立即复用当前数据重新绘图，无需重新加载 MAT 文件。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                modeHint.Layout.Row = 2;
                modeHint.Layout.Column = [5, 14];
            end
        
            isoModeText = gobjects(0);
            isoModeDropDown = gobjects(0);
            isoModeHint = gobjects(0);
            if showIsoModeControl
                isoModeText = uilabel(controls, 'Text', '等值面方式');
                isoModeText.Layout.Row = 3;
                isoModeText.Layout.Column = 1;
                isoModeDropDown = uidropdown(controls, ...
                    'Items', {'自动多层', '指定单值'}, ...
                    'ItemsData', {'automatic', 'single'}, 'Value', isoSelectionMode);
                isoModeDropDown.Layout.Row = 3;
                isoModeDropDown.Layout.Column = [2, 4];
                isoModeHint = uilabel(controls, ...
                    'Text', '自动模式修改数量/范围后重绘；指定单值模式在松开滑条后重绘。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                isoModeHint.Layout.Row = 3;
                isoModeHint.Layout.Column = [5, 14];
            end
        
            automaticControls = {};
            countText = gobjects(0);
            countSpinner = gobjects(0);
            if showCountControl
                countText = uilabel(controls, 'Text', '等值面数');
                countText.Layout.Row = 4;
                countText.Layout.Column = 1;
                countSpinner = uispinner(controls, 'Limits', [1, 12], 'Step', 1, ...
                    'RoundFractionalValues', 'on', 'Value', opts.NumIsosurfaces);
                countSpinner.Layout.Row = 4;
                countSpinner.Layout.Column = 2;
                automaticControls = [automaticControls, {countText, countSpinner}];
            end
        
            lowerText = gobjects(0);
            lowerEdit = gobjects(0);
            upperText = gobjects(0);
            upperEdit = gobjects(0);
            if showRangeControl
                lowerText = uilabel(controls, 'Text', '范围下限%');
                lowerText.Layout.Row = 4;
                lowerText.Layout.Column = 3;
                lowerEdit = uieditfield(controls, 'numeric', 'Limits', [0, 100], ...
                    'ValueDisplayFormat', '%.1f', 'Value', 100 * opts.IsoRange(1));
                lowerEdit.Layout.Row = 4;
                lowerEdit.Layout.Column = 4;
        
                upperText = uilabel(controls, 'Text', '范围上限%');
                upperText.Layout.Row = 4;
                upperText.Layout.Column = 5;
                upperEdit = uieditfield(controls, 'numeric', 'Limits', [0, 100], ...
                    'ValueDisplayFormat', '%.1f', 'Value', 100 * opts.IsoRange(2));
                upperEdit.Layout.Row = 4;
                upperEdit.Layout.Column = 6;
                automaticControls = [automaticControls, ...
                    {lowerText, lowerEdit, upperText, upperEdit}];
            end
        
            alphaText = gobjects(0);
            alphaSlider = gobjects(0);
            if showAlphaControl
                alphaText = uilabel(controls, 'Text', '透明度');
                alphaText.Layout.Row = 4;
                alphaText.Layout.Column = 7;
                alphaSlider = uislider(controls, 'Limits', [0.03, 1], ...
                    'Value', opts.SurfaceAlpha, 'MajorTicks', [0.05, 0.25, 0.5, 0.75, 1]);
                alphaSlider.Layout.Row = 4;
                alphaSlider.Layout.Column = [8, 14];
            end
        
            exactValueText = gobjects(0);
            exactValueEdit = gobjects(0);
            exactValueSlider = gobjects(0);
            exactControls = {};
            if showExactValueControl
                exactValueText = uilabel(controls, 'Text', '等值面数值');
                exactValueText.Layout.Row = 4;
                exactValueText.Layout.Column = [1, 2];
                exactValueEdit = uieditfield(controls, 'numeric', ...
                    'Limits', exactValueLimits, 'ValueDisplayFormat', '%.6g', ...
                    'Value', exactIsoValue);
                exactValueEdit.Layout.Row = 4;
                exactValueEdit.Layout.Column = [3, 4];
                exactValueSlider = uislider(controls, 'Limits', exactValueLimits, ...
                    'Value', exactIsoValue);
                exactValueSlider.Layout.Row = 4;
                if showAlphaControl
                    exactValueSlider.Layout.Column = [5, 10];
                else
                    exactValueSlider.Layout.Column = [5, 14];
                end
                matfield.Graphics.configureValueSliderTicks(exactValueSlider, globalRange);
                exactControls = {exactValueText, exactValueEdit, exactValueSlider};
            end
        
            playbackText = gobjects(0);
            playButton = gobjects(0);
            intervalText = gobjects(0);
            playbackIntervalEdit = gobjects(0);
            playbackHint = gobjects(0);
            playbackTimer = [];
            playbackControls = {};
            if showExactValueControl
                playbackText = uilabel(controls, 'Text', '单值自动播放');
                playbackText.Layout.Row = 5;
                playbackText.Layout.Column = [1, 2];
                playButton = uibutton(controls, 'push', 'Text', '播放');
                playButton.Layout.Row = 5;
                playButton.Layout.Column = [3, 4];
                intervalText = uilabel(controls, 'Text', '间隔(s)');
                intervalText.Layout.Row = 5;
                intervalText.Layout.Column = 5;
                playbackIntervalEdit = uieditfield(controls, 'numeric', ...
                    'Limits', [0.05, 10], 'ValueDisplayFormat', '%.2f', 'Value', 0.35);
                playbackIntervalEdit.Layout.Row = 5;
                playbackIntervalEdit.Layout.Column = 6;
                playbackHint = uilabel(controls, ...
                    'Text', '每帧增加全局值域的 1%，到最大值后从最小值循环。', ...
                    'FontColor', [0.35, 0.35, 0.38]);
                playbackHint.Layout.Row = 5;
                playbackHint.Layout.Column = [7, 14];
                if diff(globalRange) == 0
                    playButton.Enable = 'off';
                end
                playbackControls = {playbackText, playButton, intervalText, ...
                    playbackIntervalEdit, playbackHint};
                playbackTimer = timer('ExecutionMode', 'fixedSpacing', ...
                    'BusyMode', 'drop', 'Period', playbackIntervalEdit.Value, ...
                    'TimerFcn', @(source, event) matfield.VolumeView.advancePlayback(fig, source, event));
            end
        
            matfield.Graphics.setControlGroupVisible(automaticControls, strcmp(isoSelectionMode, 'automatic'));
            matfield.Graphics.setControlGroupVisible(exactControls, strcmp(isoSelectionMode, 'single'));
            matfield.Graphics.setControlGroupVisible(playbackControls, showExactPlaybackInitially);
            matfield.Graphics.setVolumeAlphaLayout(alphaText, alphaSlider, isoSelectionMode);
        
            controlLayout = struct( ...
                'Kind', 'volume', ...
                'Grid', controls, ...
                'VariableLabel', variableLabel, ...
                'GlobalLabel', globalLabel, ...
                'SamplingLabel', samplingLabel, ...
                'ModeText', modeText, ...
                'ModeDropDown', modeDropDown, ...
                'ModeHint', modeHint, ...
                'IsoModeText', isoModeText, ...
                'IsoModeDropDown', isoModeDropDown, ...
                'IsoModeHint', isoModeHint, ...
                'CountText', countText, ...
                'CountSpinner', countSpinner, ...
                'LowerText', lowerText, ...
                'LowerEdit', lowerEdit, ...
                'UpperText', upperText, ...
                'UpperEdit', upperEdit, ...
                'ExactValueText', exactValueText, ...
                'ExactValueEdit', exactValueEdit, ...
                'ExactValueSlider', exactValueSlider, ...
                'AlphaText', alphaText, ...
                'AlphaSlider', alphaSlider, ...
                'PlaybackText', playbackText, ...
                'PlayButton', playButton, ...
                'IntervalText', intervalText, ...
                'PlaybackIntervalEdit', playbackIntervalEdit, ...
                'PlaybackHint', playbackHint);
        
            if isnumeric(opts.ColorLimits)
                volumeClim = matfield.Graphics.makeSafeLimits(opts.ColorLimits);
            else
                volumeClim = matfield.Graphics.makeSafeLimits(globalRange);
            end
        
            state = struct( ...
                'Data', volumeData, ...
                'DataSize', size(volumeData), ...
                'FieldDimension', 3, ...
                'HasRendered', false, ...
                'Variable', opts.Variable, ...
                'PlotMode', 'volume', ...
                'Options', opts, ...
                'GlobalRange', globalRange, ...
                'ColorLimits', volumeClim, ...
                'NumIsosurfaces', opts.NumIsosurfaces, ...
                'IsoRange', opts.IsoRange, ...
                'IsoValues', opts.IsoValues, ...
                'IsoSelectionMode', isoSelectionMode, ...
                'ExactIsoValue', exactIsoValue, ...
                'SurfaceAlpha', opts.SurfaceAlpha, ...
                'Axes', ax, ...
                'AxesToolbar', gobjects(0), ...
                'ToolbarButtons', gobjects(0), ...
                'Colorbar', cb, ...
                'SampleIndices', {sampleIndices}, ...
                'FilePathEdit', filePathEdit, ...
                'BrowseButton', browseButton, ...
                'VariableDropDown', variableDropDown, ...
                'ModeDropDown', modeDropDown, ...
                'IsoModeDropDown', isoModeDropDown, ...
                'CountSpinner', countSpinner, ...
                'LowerEdit', lowerEdit, ...
                'UpperEdit', upperEdit, ...
                'ExactValueEdit', exactValueEdit, ...
                'ExactValueSlider', exactValueSlider, ...
                'AutomaticControls', {automaticControls}, ...
                'ExactControls', {exactControls}, ...
                'PlaybackControls', {playbackControls}, ...
                'AlphaText', alphaText, ...
                'AlphaSlider', alphaSlider, ...
                'PlayButton', playButton, ...
                'PlaybackIntervalEdit', playbackIntervalEdit, ...
                'PlaybackTimer', playbackTimer, ...
                'MainGrid', mainGrid, ...
                'ControlsGrid', controls, ...
                'ControlPanelRow', controlRow, ...
                'BaseControlPanelHeight', baseControlPanelHeight, ...
                'LastAlphaRenderClock', tic, ...
                'Patches', gobjects(0), ...
                'Layout', matfield.Layout.makeViewerLayout(shell, controlLayout, 'volume'));
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
            if ~isempty(isoModeDropDown) && isgraphics(isoModeDropDown)
                isoModeDropDown.ValueChangedFcn = ...
                    @(source, event) matfield.VolumeView.onIsoSelectionModeChanged(fig, source, event);
            end
            if ~isempty(countSpinner) && isgraphics(countSpinner)
                countSpinner.ValueChangedFcn = ...
                    @(source, event) matfield.VolumeView.onAutomaticIsoParametersChanged(fig, source, event);
            end
            if ~isempty(lowerEdit) && isgraphics(lowerEdit)
                lowerEdit.ValueChangedFcn = ...
                    @(source, event) matfield.VolumeView.onAutomaticIsoParametersChanged(fig, source, event);
                upperEdit.ValueChangedFcn = ...
                    @(source, event) matfield.VolumeView.onAutomaticIsoParametersChanged(fig, source, event);
            end
            if ~isempty(exactValueSlider) && isgraphics(exactValueSlider)
                exactValueSlider.ValueChangingFcn = ...
                    @(source, event) matfield.VolumeView.previewExactIsoValue(fig, event.Value);
                exactValueSlider.ValueChangedFcn = ...
                    @(source, event) matfield.VolumeView.commitExactIsoValue(fig, source.Value);
                exactValueEdit.ValueChangedFcn = ...
                    @(source, event) matfield.VolumeView.commitExactIsoValue(fig, source.Value);
            end
            if ~isempty(alphaSlider) && isgraphics(alphaSlider)
                alphaSlider.ValueChangingFcn = ...
                    @(source, event) matfield.VolumeView.changeSurfaceAlpha(fig, event.Value, false);
                alphaSlider.ValueChangedFcn = ...
                    @(source, event) matfield.VolumeView.changeSurfaceAlpha(fig, source.Value, true);
            end
            if ~isempty(playButton) && isgraphics(playButton)
                playButton.ButtonPushedFcn = @(source, event) matfield.Playback.toggleViewerPlayback(fig, source, event);
                playbackIntervalEdit.ValueChangedFcn = ...
                    @(source, event) matfield.Playback.updateViewerPlaybackPeriod(fig, source, event);
            end
        
            matfield.VolumeView.renderVolume(fig);
            matfield.Layout.enableResponsiveViewerLayout(fig);
        end

        function onAutomaticIsoParametersChanged(fig, ~, ~)
            if isvalid(fig)
                matfield.VolumeView.renderVolume(fig);
            end
        end

        function changeSurfaceAlpha(fig, alphaValue, synchronizeSlider)
            if ~isvalid(fig)
                return
            end
            if nargin < 3
                synchronizeSlider = true;
            end
            state = fig.UserData;
            if ~synchronizeSlider && toc(state.LastAlphaRenderClock) < 0.03
                state.SurfaceAlpha = alphaValue;
                fig.UserData = state;
                return
            end
            state.LastAlphaRenderClock = tic;
            validPatches = state.Patches(isgraphics(state.Patches));
            if ~isempty(validPatches)
                set(validPatches, 'FaceAlpha', alphaValue);
            end
            state.SurfaceAlpha = alphaValue;
            if synchronizeSlider && ~isempty(state.AlphaSlider) && isgraphics(state.AlphaSlider)
                state.AlphaSlider.Value = alphaValue;
            end
            fig.UserData = state;
            drawnow limitrate nocallbacks
        end

        function onIsoSelectionModeChanged(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            matfield.Playback.pauseViewerPlayback(fig);
            state = fig.UserData;
            state.IsoSelectionMode = char(source.Value);
            matfield.Graphics.setControlGroupVisible(state.AutomaticControls, ...
                strcmp(state.IsoSelectionMode, 'automatic'));
            matfield.Graphics.setControlGroupVisible(state.ExactControls, ...
                strcmp(state.IsoSelectionMode, 'single'));
            showPlayback = strcmp(state.IsoSelectionMode, 'single');
            matfield.Graphics.setControlGroupVisible(state.PlaybackControls, showPlayback);
            fig.UserData = state;
            matfield.Layout.applyResponsiveViewerLayout(fig, true);
            matfield.VolumeView.renderVolume(fig);
        end

        function previewExactIsoValue(fig, value)
            if ~isvalid(fig)
                return
            end
            matfield.Playback.pauseViewerPlayback(fig);
            state = fig.UserData;
            state.ExactIsoValue = double(value);
            if ~isempty(state.ExactValueEdit) && isgraphics(state.ExactValueEdit)
                state.ExactValueEdit.Value = state.ExactIsoValue;
            end
            fig.UserData = state;
        end

        function commitExactIsoValue(fig, value)
            if ~isvalid(fig)
                return
            end
            matfield.Playback.pauseViewerPlayback(fig);
            state = fig.UserData;
            state.ExactIsoValue = double(value);
            if ~isempty(state.ExactValueEdit) && isgraphics(state.ExactValueEdit)
                state.ExactValueEdit.Value = state.ExactIsoValue;
                state.ExactValueSlider.Value = state.ExactIsoValue;
            end
            fig.UserData = state;
            matfield.VolumeView.renderVolume(fig);
        end

        function renderVolume(fig)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            isoRange = state.IsoRange;
            if ~isempty(state.LowerEdit) && isgraphics(state.LowerEdit)
                isoRange = [state.LowerEdit.Value, state.UpperEdit.Value] / 100;
                if isoRange(1) >= isoRange(2)
                    uialert(fig, '范围下限必须小于范围上限。', '等值面范围无效');
                    return
                end
            end
            count = state.NumIsosurfaces;
            if ~isempty(state.CountSpinner) && isgraphics(state.CountSpinner)
                count = round(state.CountSpinner.Value);
            end
            surfaceAlpha = state.SurfaceAlpha;
            if ~isempty(state.AlphaSlider) && isgraphics(state.AlphaSlider)
                surfaceAlpha = state.AlphaSlider.Value;
            end
            exactIsoValue = state.ExactIsoValue;
            if strcmp(state.IsoSelectionMode, 'single') && ...
                    ~isempty(state.ExactValueEdit) && isgraphics(state.ExactValueEdit)
                exactIsoValue = state.ExactValueEdit.Value;
            end
        
            if state.HasRendered
                navigationState = matfield.VolumeView.captureAxesNavigation(state.Axes);
            else
                navigationState = [];
            end
        
            valueSpan = diff(state.GlobalRange);
            cla(state.Axes);
            hold(state.Axes, 'on');
            state.Axes.CLim = state.ColorLimits;
            dim1Indices = state.SampleIndices{1};
            dim2Indices = state.SampleIndices{2};
            dim3Indices = state.SampleIndices{3};
        
            if valueSpan == 0
                text(state.Axes, mean(dim1Indices), mean(dim2Indices), ...
                    mean(dim3Indices), ...
                    sprintf('常量场：%s', matfield.Graphics.formatNumber(state.GlobalRange(1))), ...
                    'HorizontalAlignment', 'center', 'FontSize', 14);
                levels = state.GlobalRange(1);
                patches = gobjects(0);
            else
                if strcmp(state.IsoSelectionMode, 'single')
                    levels = exactIsoValue;
                elseif ~isempty(state.IsoValues)
                    levels = state.IsoValues;
                else
                    levelBounds = state.GlobalRange(1) + valueSpan * isoRange;
                    levels = linspace(levelBounds(1), levelBounds(2), count);
                end
        
                sampled = state.Data(dim1Indices, dim2Indices, dim3Indices);
                sampled(~isfinite(sampled)) = NaN;
        
                % Permute the first two array dimensions so meshgrid coordinates
                % correspond to array dimensions 1/2/3 respectively.
                sampledForPlot = permute(sampled, [2, 1, 3]);
                [coord1, coord2, coord3] = meshgrid( ...
                    dim1Indices, dim2Indices, dim3Indices);
                map = colormap(state.Axes);
                patches = gobjects(0);
        
                for level = levels
                    facesAndVertices = isosurface(coord1, coord2, coord3, sampledForPlot, level);
                    if isempty(facesAndVertices.vertices)
                        continue
                    end
                    colorPosition = (level - state.ColorLimits(1)) / diff(state.ColorLimits);
                    colorIndex = 1 + round(max(0, min(1, colorPosition)) * (size(map, 1) - 1));
                    surfacePatch = patch(state.Axes, facesAndVertices, ...
                        'FaceColor', map(colorIndex, :), ...
                        'EdgeColor', 'none', ...
                        'FaceAlpha', surfaceAlpha, ...
                        'AmbientStrength', 0.28, ...
                        'DiffuseStrength', 0.72, ...
                        'SpecularStrength', 0.12);
                    try
                        isonormals(coord1, coord2, coord3, sampledForPlot, surfacePatch);
                    catch
                        % Faceted normals are still a valid fallback for unusual data.
                    end
                    patches(end + 1) = surfacePatch; %#ok<AGROW>
                end
            end
        
            hold(state.Axes, 'off');
            grid(state.Axes, 'on');
            box(state.Axes, 'on');
            state.Axes.XLim = matfield.Graphics.makeSafeLimits([dim1Indices(1), dim1Indices(end)]);
            state.Axes.YLim = matfield.Graphics.makeSafeLimits([dim2Indices(1), dim2Indices(end)]);
            state.Axes.ZLim = matfield.Graphics.makeSafeLimits([dim3Indices(1), dim3Indices(end)]);
            axis(state.Axes, 'vis3d');
            daspect(state.Axes, [1, 1, 1]);
            if state.HasRendered
                matfield.VolumeView.restoreAxesNavigation(state.Axes, navigationState);
            else
                view(state.Axes, 42, 26);
                % Let MATLAB fit the rotated box first, then pull the camera back a
                % little farther so the title and tick labels remain inside UIAxes.
                state.Axes.CameraViewAngleMode = 'auto';
                drawnow limitrate nocallbacks
                camzoom(state.Axes, 0.84);
                axis(state.Axes, 'vis3d');
            end
            delete(findall(state.Axes, 'Type', 'light'));
            if ~isempty(patches)
                camlight(state.Axes, 'headlight');
                lighting(state.Axes, 'gouraud');
            end
            xlabel(state.Axes, 'Dim 1 index');
            ylabel(state.Axes, 'Dim 2 index');
            zlabel(state.Axes, 'Dim 3 index');
            if isscalar(levels)
                titleText = sprintf('%s  |  isosurface = %s', ...
                    state.Variable, matfield.Graphics.formatNumber(levels));
            else
                titleText = sprintf('%s  |  %d isosurfaces: %s ... %s', ...
                    state.Variable, numel(patches), matfield.Graphics.formatNumber(levels(1)), ...
                    matfield.Graphics.formatNumber(levels(end)));
            end
            title(state.Axes, titleText, 'Interpreter', 'none');
        
            state.NumIsosurfaces = count;
            state.IsoRange = isoRange;
            state.ExactIsoValue = exactIsoValue;
            state.SurfaceAlpha = surfaceAlpha;
            state.Patches = patches;
            state.HasRendered = true;
            state = matfield.VolumeView.ensureVolumeInteractivity(state);
            fig.UserData = state;
            drawnow
            matfield.Graphics.refreshColorbarPresentation(state.Colorbar);
        end

        function state = ensureVolumeInteractivity(state)
            ax = state.Axes;
        
            % The default toolbar of a newly created UIAxes has no concrete button
            % objects. Because this axes only becomes 3-D after its first render,
            % MATLAB can fail to materialize the 3-D toolbar. Create the tools
            % explicitly after rendering, when the axes is already in a 3-D view.
            enableDefaultInteractivity(ax);
            if isempty(state.AxesToolbar) || ~isvalid(state.AxesToolbar)
                [state.AxesToolbar, state.ToolbarButtons] = axtoolbar(ax, ...
                    {'rotate', 'pan', 'zoomin', 'zoomout', 'restoreview'});
            end
            state.AxesToolbar.Visible = 'on';
            ax.Toolbar.Visible = 'on';
        end

        function navigationState = captureAxesNavigation(ax)
            navigationState = struct( ...
                'XLim', ax.XLim, ...
                'YLim', ax.YLim, ...
                'ZLim', ax.ZLim, ...
                'CameraPosition', ax.CameraPosition, ...
                'CameraPositionMode', ax.CameraPositionMode, ...
                'CameraTarget', ax.CameraTarget, ...
                'CameraTargetMode', ax.CameraTargetMode, ...
                'CameraUpVector', ax.CameraUpVector, ...
                'CameraUpVectorMode', ax.CameraUpVectorMode, ...
                'CameraViewAngle', ax.CameraViewAngle, ...
                'CameraViewAngleMode', ax.CameraViewAngleMode, ...
                'Projection', ax.Projection);
        end

        function restoreAxesNavigation(ax, navigationState)
            ax.XLim = navigationState.XLim;
            ax.YLim = navigationState.YLim;
            ax.ZLim = navigationState.ZLim;
            ax.CameraPosition = navigationState.CameraPosition;
            ax.CameraTarget = navigationState.CameraTarget;
            ax.CameraUpVector = navigationState.CameraUpVector;
            ax.CameraViewAngle = navigationState.CameraViewAngle;
            ax.Projection = navigationState.Projection;
        
            % Assigning any camera value forces its corresponding mode to manual.
            % Restore the modes last so a redraw does not silently change how pan
            % and zoom operate. Manual modes still retain the exact user camera;
            % automatic modes remain managed by MATLAB as they were before redraw.
            ax.CameraPositionMode = navigationState.CameraPositionMode;
            ax.CameraTargetMode = navigationState.CameraTargetMode;
            ax.CameraUpVectorMode = navigationState.CameraUpVectorMode;
            ax.CameraViewAngleMode = navigationState.CameraViewAngleMode;
        end

        function advancePlayback(fig, ~, ~)
            %ADVANCEPLAYBACK Advance one exact-isovalue frame and wrap the range.
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            valueSpan = diff(state.GlobalRange);
            if valueSpan <= 0
                matfield.Playback.pauseViewerPlayback(fig);
                return
            end
            nextValue = state.ExactIsoValue + valueSpan / 100;
            if nextValue > state.GlobalRange(2)
                nextValue = state.GlobalRange(1);
            end
            state.ExactIsoValue = nextValue;
            state.ExactValueEdit.Value = nextValue;
            state.ExactValueSlider.Value = nextValue;
            fig.UserData = state;
            matfield.VolumeView.renderVolume(fig);
        end

    end
end
