classdef SelectionView
    %SELECTIONVIEW Build the empty viewer state used before a variable is selected.
    methods (Static)
        function fig = createVariableSelectionFigure(opts, existingFig)
            if nargin < 2
                existingFig = [];
            end
            switch opts.PlotType
                case 'slice'
                    showMode = ~opts.Specified.PlotType;
                    showDimension = ~opts.Specified.Dimension;
                    showIndex = ~opts.Specified.Index;
                    showColor = ~opts.Specified.ColorLimits;
                    showControlRow = showDimension || showIndex || showColor;
                    panelHeight = 100 + 34 * double(showMode) + ...
                        42 * double(showControlRow) + 42 * double(showColor) + ...
                        36 * double(showIndex);
                    figName = '请选择目标变量 | slice';
                    panelTitle = '切片控制';
                case 'volume'
                    showMode = ~opts.Specified.PlotType;
                    useExactValues = opts.Specified.IsoValues;
                    automaticSpecified = opts.Specified.NumIsosurfaces || opts.Specified.IsoRange;
                    showIsoMode = ~useExactValues && ~automaticSpecified;
                    showVolumeRow = (~useExactValues && ~opts.Specified.NumIsosurfaces) || ...
                        (~useExactValues && ~opts.Specified.IsoRange) || ...
                        ~opts.Specified.SurfaceAlpha;
                    panelHeight = 100 + 34 * double(showMode) + ...
                        36 * double(showIsoMode) + 46 * double(showVolumeRow);
                    figName = '请选择目标变量 | 3-D isosurfaces';
                    panelTitle = '三维等值面控制';
            end
        
            if ~matfield.Data.isReady(opts.Source)
                figName = '请选择数据源';
            elseif strcmp(opts.Source.Type, 'workspace')
                figName = '请选择 Base Workspace 变量';
            elseif strcmp(opts.Source.Type, 'memory')
                figName = '请选择内存变量中的目标字段';
            end
        
            fig = matfield.Viewer.prepareViewerFigure(existingFig, figName, ...
                [120, 70, 1180, 830], opts.Visible);
            shell = matfield.Viewer.createViewerShell(fig, opts, '', panelTitle, panelHeight, false);
            mainGrid = shell.MainGrid;
            ax = shell.Axes;
            ax.Visible = 'off';
            ax.Toolbar.Visible = 'off';
            controlPanel = shell.ControlPanel;
            switch opts.PlotType
                case 'slice'
                    [controls, controlLayout] = matfield.SelectionView.createDisabledSliceControls(controlPanel, opts);
                case 'volume'
                    [controls, controlLayout] = matfield.SelectionView.createDisabledVolumeControls(controlPanel, opts);
            end
        
            fig.UserData = struct( ...
                'MatFile', opts.MatFile, ...
                'Source', opts.Source, ...
                'Variable', '', ...
                'PlotMode', opts.PlotType, ...
                'Options', opts, ...
                'Axes', ax, ...
                'SourceTypeDropDown', shell.SourceTypeDropDown, ...
                'FilePathEdit', shell.FilePathEdit, ...
                'BrowseButton', shell.BrowseButton, ...
                'WorkspaceRefreshButton', shell.WorkspaceRefreshButton, ...
                'VariableDropDown', shell.VariableDropDown, ...
                'PlayButton', gobjects(0), ...
                'PlaybackTimer', [], ...
                'MainGrid', mainGrid, ...
                'ControlsGrid', controls, ...
                'ControlPanelRow', shell.ControlPanelRow, ...
                'Layout', matfield.Layout.makeViewerLayout(shell, controlLayout, opts.PlotType));
            matfield.Viewer.wireSourceCallbacks(fig, shell);
            matfield.Layout.enableResponsiveViewerLayout(fig);
        end

        function [controls, layout] = createDisabledSliceControls(controlPanel, opts)
            showMode = ~opts.Specified.PlotType;
            showDimension = ~opts.Specified.Dimension;
            showIndex = ~opts.Specified.Index;
            showColor = ~opts.Specified.ColorLimits;
            showControlRow = showDimension || showIndex || showColor;
        
            controls = uigridlayout(controlPanel, [5, 14]);
            controls.RowHeight = {28, 34 * double(showMode), ...
                42 * double(showControlRow), 42 * double(showColor), ...
                36 * double(showIndex)};
            controls.ColumnWidth = {62, 130, 42, '1x', '1x', '1x', ...
                72, 16, 72, 120, 34, 80, 34, 80};
            controls.Padding = [10, 14, 10, 8];
            controls.ColumnSpacing = 7;
            controls.RowSpacing = 6;
            controls.Scrollable = 'on';
        
            variableLabel = uilabel(controls, 'Text', '变量：尚未选择', 'FontWeight', 'bold');
            variableLabel.Layout.Row = 1;
            variableLabel.Layout.Column = [1, 3];
            globalLabel = uilabel(controls, 'Text', '全局 [min, max]：-- / --');
            globalLabel.Layout.Row = 1;
            globalLabel.Layout.Column = [4, 7];
            sliceLabel = uilabel(controls, 'Text', '切片 [min, max]：-- / --');
            sliceLabel.Layout.Row = 1;
            sliceLabel.Layout.Column = [8, 14];
        
            modeText = gobjects(0);
            modeDropDown = gobjects(0);
            if showMode
                modeText = uilabel(controls, 'Text', '绘图模式', 'Enable', 'off');
                modeText.Layout.Row = 2;
                modeText.Layout.Column = 1;
                modeDropDown = uidropdown(controls, 'Items', {'Slice（二维切片）'}, ...
                    'Value', 'Slice（二维切片）', 'Enable', 'off');
                modeDropDown.Layout.Row = 2;
                modeDropDown.Layout.Column = [2, 4];
            end
        
            dimensionText = gobjects(0);
            dimensionDropDown = gobjects(0);
            if showDimension
                dimensionText = uilabel(controls, 'Text', '切片维度', 'Enable', 'off');
                dimensionText.Layout.Row = 3;
                dimensionText.Layout.Column = 1;
                dimensionDropDown = uidropdown(controls, ...
                    'Items', {'Dim 1', 'Dim 2', 'Dim 3'}, ...
                    'Value', 'Dim 3', 'Enable', 'off');
                dimensionDropDown.Layout.Row = 3;
                dimensionDropDown.Layout.Column = 2;
            end
        
            indexText = gobjects(0);
            indexSlider = gobjects(0);
            indexEdit = gobjects(0);
            playbackText = gobjects(0);
            playButton = gobjects(0);
            intervalText = gobjects(0);
            playbackIntervalEdit = gobjects(0);
            if showIndex
                indexText = uilabel(controls, 'Text', '索引', 'Enable', 'off');
                indexText.Layout.Row = 3;
                indexText.Layout.Column = 3;
                indexSlider = uislider(controls, 'Limits', [1, 2], 'Value', 1, ...
                    'MajorTicks', [1, 2], 'Enable', 'off');
                indexSlider.Layout.Row = 3;
                indexSlider.Layout.Column = [4, 6];
                indexEdit = uieditfield(controls, 'numeric', 'Value', 1, 'Enable', 'off');
                indexEdit.Layout.Row = 3;
                indexEdit.Layout.Column = 7;
                playbackText = uilabel(controls, 'Text', '自动播放', 'Enable', 'off');
                playbackText.Layout.Row = 5;
                playbackText.Layout.Column = 1;
                playButton = uibutton(controls, 'Text', '播放', 'Enable', 'off');
                playButton.Layout.Row = 5;
                playButton.Layout.Column = 2;
                intervalText = uilabel(controls, 'Text', '间隔(s)', 'Enable', 'off');
                intervalText.Layout.Row = 5;
                intervalText.Layout.Column = 3;
                playbackIntervalEdit = uieditfield(controls, 'numeric', ...
                    'Value', 0.12, 'Enable', 'off');
                playbackIntervalEdit.Layout.Row = 5;
                playbackIntervalEdit.Layout.Column = 4;
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
            if showColor
                colorText = uilabel(controls, 'Text', '颜色栏范围', 'Enable', 'off');
                colorText.Layout.Row = 3;
                colorText.Layout.Column = 9;
                colorDropDown = uidropdown(controls, 'Items', {'全局范围'}, ...
                    'Value', '全局范围', 'Enable', 'off');
                colorDropDown.Layout.Row = 3;
                colorDropDown.Layout.Column = 10;
                colorLowerText = uilabel(controls, 'Text', '下限', 'Enable', 'off');
                colorLowerText.Layout.Row = 3;
                colorLowerText.Layout.Column = 11;
                colorLowerEdit = uieditfield(controls, 'numeric', ...
                    'Value', 0, 'Enable', 'off');
                colorLowerEdit.Layout.Row = 3;
                colorLowerEdit.Layout.Column = 12;
                colorUpperText = uilabel(controls, 'Text', '上限', 'Enable', 'off');
                colorUpperText.Layout.Row = 3;
                colorUpperText.Layout.Column = 13;
                colorUpperEdit = uieditfield(controls, 'numeric', ...
                    'Value', 1, 'Enable', 'off');
                colorUpperEdit.Layout.Row = 3;
                colorUpperEdit.Layout.Column = 14;
        
                colorLowerSliderText = uilabel(controls, 'Text', '下限粗调', 'Enable', 'off');
                colorLowerSliderText.Layout.Row = 4;
                colorLowerSliderText.Layout.Column = [1, 2];
                colorLowerSlider = uislider(controls, 'Limits', [0, 1], ...
                    'Value', 0, 'Enable', 'off');
                colorLowerSlider.Layout.Row = 4;
                colorLowerSlider.Layout.Column = [3, 7];
                colorUpperSliderText = uilabel(controls, 'Text', '上限粗调', 'Enable', 'off');
                colorUpperSliderText.Layout.Row = 4;
                colorUpperSliderText.Layout.Column = [8, 9];
                colorUpperSlider = uislider(controls, 'Limits', [0, 1], ...
                    'Value', 1, 'Enable', 'off');
                colorUpperSlider.Layout.Row = 4;
                colorUpperSlider.Layout.Column = [10, 14];
            end
            layout = struct( ...
                'Kind', 'slice', 'Grid', controls, ...
                'VariableLabel', variableLabel, 'GlobalLabel', globalLabel, ...
                'SliceLabel', sliceLabel, 'ModeText', modeText, ...
                'ModeDropDown', modeDropDown, 'ModeHint', gobjects(0), ...
                'DimensionText', dimensionText, 'DimensionDropDown', dimensionDropDown, ...
                'IndexText', indexText, 'IndexSlider', indexSlider, 'IndexEdit', indexEdit, ...
                'ColorText', colorText, 'ColorDropDown', colorDropDown, ...
                'ColorLowerText', colorLowerText, 'ColorLowerEdit', colorLowerEdit, ...
                'ColorUpperText', colorUpperText, 'ColorUpperEdit', colorUpperEdit, ...
                'ColorLowerSliderText', colorLowerSliderText, ...
                'ColorLowerSlider', colorLowerSlider, ...
                'ColorUpperSliderText', colorUpperSliderText, ...
                'ColorUpperSlider', colorUpperSlider, ...
                'PlaybackText', playbackText, 'PlayButton', playButton, ...
                'IntervalText', intervalText, ...
                'PlaybackIntervalEdit', playbackIntervalEdit, ...
                'PlaybackHint', gobjects(0));
        end

        function [controls, layout] = createDisabledVolumeControls(controlPanel, opts)
            showMode = ~opts.Specified.PlotType;
            useExactValues = opts.Specified.IsoValues;
            automaticSpecified = opts.Specified.NumIsosurfaces || opts.Specified.IsoRange;
            showIsoMode = ~useExactValues && ~automaticSpecified;
            showCount = ~useExactValues && ~opts.Specified.NumIsosurfaces;
            showRange = ~useExactValues && ~opts.Specified.IsoRange;
            showAlpha = ~opts.Specified.SurfaceAlpha;
            showVolumeRow = showCount || showRange || showAlpha;
        
            controls = uigridlayout(controlPanel, [4, 14]);
            controls.RowHeight = {28, 34 * double(showMode), ...
                36 * double(showIsoMode), 46 * double(showVolumeRow)};
            controls.ColumnWidth = {82, 62, 76, 62, 76, 62, 55, ...
                '1x', '1x', '1x', 55, 62, 62, 72};
            controls.Padding = [10, 14, 10, 8];
            controls.ColumnSpacing = 7;
            controls.RowSpacing = 6;
        
            controls.Scrollable = 'on';
            variableLabel = uilabel(controls, 'Text', '变量：尚未选择', 'FontWeight', 'bold');
            variableLabel.Layout.Row = 1;
            variableLabel.Layout.Column = [1, 5];
            globalLabel = uilabel(controls, 'Text', '全局 [min, max]：-- / --');
            globalLabel.Layout.Row = 1;
            globalLabel.Layout.Column = [6, 9];
            sampleLabel = uilabel(controls, 'Text', '绘制采样：--');
            sampleLabel.Layout.Row = 1;
            sampleLabel.Layout.Column = [10, 14];
        
            modeText = gobjects(0);
            modeDropDown = gobjects(0);
            if showMode
                modeText = uilabel(controls, 'Text', '绘图模式', 'Enable', 'off');
                modeText.Layout.Row = 2;
                modeText.Layout.Column = 1;
                modeDropDown = uidropdown(controls, 'Items', {'Volume（三维等值面）'}, ...
                    'Value', 'Volume（三维等值面）', 'Enable', 'off');
                modeDropDown.Layout.Row = 2;
                modeDropDown.Layout.Column = [2, 4];
            end
        
            isoModeText = gobjects(0);
            isoModeDropDown = gobjects(0);
            if showIsoMode
                isoModeText = uilabel(controls, 'Text', '等值面方式', 'Enable', 'off');
                isoModeText.Layout.Row = 3;
                isoModeText.Layout.Column = 1;
                isoModeDropDown = uidropdown(controls, 'Items', {'自动多层'}, ...
                    'Value', '自动多层', 'Enable', 'off');
                isoModeDropDown.Layout.Row = 3;
                isoModeDropDown.Layout.Column = [2, 4];
            end
        
            countText = gobjects(0);
            countSpinner = gobjects(0);
            if showCount
                countText = uilabel(controls, 'Text', '等值面数', 'Enable', 'off');
                countText.Layout.Row = 4;
                countText.Layout.Column = 1;
                countSpinner = uispinner(controls, 'Value', opts.NumIsosurfaces, 'Enable', 'off');
                countSpinner.Layout.Row = 4;
                countSpinner.Layout.Column = 2;
            end
        
            lowerText = gobjects(0);
            lowerEdit = gobjects(0);
            upperText = gobjects(0);
            upperEdit = gobjects(0);
            if showRange
                lowerText = uilabel(controls, 'Text', '范围下限%', 'Enable', 'off');
                lowerText.Layout.Row = 4;
                lowerText.Layout.Column = 3;
                lowerEdit = uieditfield(controls, 'numeric', ...
                    'Value', 100 * opts.IsoRange(1), 'Enable', 'off');
                lowerEdit.Layout.Row = 4;
                lowerEdit.Layout.Column = 4;
                upperText = uilabel(controls, 'Text', '范围上限%', 'Enable', 'off');
                upperText.Layout.Row = 4;
                upperText.Layout.Column = 5;
                upperEdit = uieditfield(controls, 'numeric', ...
                    'Value', 100 * opts.IsoRange(2), 'Enable', 'off');
                upperEdit.Layout.Row = 4;
                upperEdit.Layout.Column = 6;
            end
        
            alphaText = gobjects(0);
            alphaSlider = gobjects(0);
            if showAlpha
                alphaText = uilabel(controls, 'Text', '透明度', 'Enable', 'off');
                alphaText.Layout.Row = 4;
                alphaText.Layout.Column = 7;
                alphaSlider = uislider(controls, 'Limits', [0.03, 1], ...
                    'Value', opts.SurfaceAlpha, 'Enable', 'off');
                alphaSlider.Layout.Row = 4;
                alphaSlider.Layout.Column = [8, 14];
            end
            layout = struct( ...
                'Kind', 'volume', 'Grid', controls, ...
                'VariableLabel', variableLabel, 'GlobalLabel', globalLabel, ...
                'SamplingLabel', sampleLabel, 'ModeText', modeText, ...
                'ModeDropDown', modeDropDown, 'ModeHint', gobjects(0), ...
                'IsoModeText', isoModeText, 'IsoModeDropDown', isoModeDropDown, ...
                'IsoModeHint', gobjects(0), 'CountText', countText, ...
                'CountSpinner', countSpinner, 'LowerText', lowerText, ...
                'LowerEdit', lowerEdit, 'UpperText', upperText, 'UpperEdit', upperEdit, ...
                'ExactValueText', gobjects(0), 'ExactValueEdit', gobjects(0), ...
                'ExactValueSlider', gobjects(0), 'AlphaText', alphaText, ...
                'AlphaSlider', alphaSlider, 'PlaybackText', gobjects(0), ...
                'PlayButton', gobjects(0), 'IntervalText', gobjects(0), ...
                'PlaybackIntervalEdit', gobjects(0), 'PlaybackHint', gobjects(0));
        end

    end
end
