classdef Layout
    %LAYOUT Apply responsive source, plot, and control-region layouts.
    methods (Static)
        function layout = makeViewerLayout(shell, controlLayout, plotMode)
            layout = struct( ...
                'RootPanel', shell.RootPanel, ...
                'MainGrid', shell.MainGrid, ...
                'PlotGrid', shell.PlotGrid, ...
                'ControlPanel', shell.ControlPanel, ...
                'ControlPanelRow', shell.ControlPanelRow, ...
                'Source', shell.SourceLayout, ...
                'Control', controlLayout, ...
                'PlotMode', plotMode, ...
                'HasColorbar', shell.HasColorbar, ...
                'Profile', '');
        end

        function enableResponsiveViewerLayout(fig)
            if ~isvalid(fig)
                return
            end
            fig.AutoResizeChildren = 'off';
            fig.SizeChangedFcn = @(source, event) matfield.Layout.applyResponsiveViewerLayout(source);
            matfield.Layout.applyResponsiveViewerLayout(fig, true);
        end

        function applyResponsiveViewerLayout(fig, forceReflow)
            if ~isvalid(fig)
                return
            end
            if nargin < 2
                forceReflow = false;
            end
            state = fig.UserData;
            if ~isstruct(state) || ~isfield(state, 'Layout') || ...
                    isempty(state.Layout) || ~isgraphics(state.Layout.MainGrid)
                return
            end
        
            figureSize = fig.Position(3:4);
            if figureSize(1) >= 1050
                profile = 'wide';
                outerPadding = 18;
            elseif figureSize(1) >= 700
                profile = 'compact';
                outerPadding = 12;
            else
                profile = 'narrow';
                outerPadding = 8;
            end
        
            layout = state.Layout;
            layout.RootPanel.Position = [1, 1, figureSize];
            layout.MainGrid.Padding = repmat(outerPadding, 1, 4);
            if forceReflow || ~strcmp(layout.Profile, profile)
                sourceHeight = matfield.Layout.applySourceSelectorLayout(layout.Source, profile);
                switch layout.Control.Kind
                    case 'slice'
                        preferredControlHeight = matfield.Layout.applySliceControlLayout(layout.Control, profile);
                    case 'volume'
                        preferredControlHeight = matfield.Layout.applyVolumeControlLayout(layout.Control, profile, state);
                    otherwise
                        preferredControlHeight = matfield.Layout.currentGridPanelHeight(layout.Control.Grid);
                end
            else
                sourceHeight = matfield.Layout.currentSourceSelectorHeight(layout.Source);
                preferredControlHeight = matfield.Layout.currentGridPanelHeight(layout.Control.Grid);
            end
        
            if layout.HasColorbar
                % The axes is still managed entirely by uigridlayout.  This stable
                % gutter belongs to the plot region, so tick labels and the colorbar
                % label cannot spill outside the figure when the window is resized.
                layout.PlotGrid.Padding = [0, 0, 132, 26];
            else
                layout.PlotGrid.Padding = [0, 0, 0, 0];
            end
        
            numberOfGaps = 1 + double(sourceHeight > 0);
            minimumPlotHeight = 220 * double(layout.HasColorbar) + ...
                120 * double(~layout.HasColorbar);
            availableForControls = figureSize(2) - 2 * outerPadding - ...
                sourceHeight - minimumPlotHeight - numberOfGaps * layout.MainGrid.RowSpacing;
            controlHeight = min(preferredControlHeight, max(120, availableForControls));
            if sourceHeight > 0
                layout.MainGrid.RowHeight = {sourceHeight, '1x', controlHeight};
            else
                layout.MainGrid.RowHeight = {'1x', controlHeight};
            end
        
            layout.Profile = profile;
            state.Layout = layout;
            fig.UserData = state;
        end

        function height = applySourceSelectorLayout(layout, profile)
            if isempty(layout.Grid) || ~isgraphics(layout.Grid)
                height = 0;
                return
            end
            grid = layout.Grid;
            if strcmp(profile, 'wide')
                matfield.Layout.prepareGridColumns(grid, 4);
                grid.ColumnWidth = {82, '2x', 86, '1x'};
                if layout.ShowFileControl
                    grid.RowHeight = {32, 32};
                    matfield.Layout.setGridItemLayout(layout.FileLabel, 1, 1);
                    matfield.Layout.setGridItemLayout(layout.FilePathEdit, 1, 2);
                    matfield.Layout.setGridItemLayout(layout.BrowseButton, 1, 3);
                    matfield.Layout.setGridItemLayout(layout.FileHint, 1, 4);
                    variableRow = 2;
                else
                    grid.RowHeight = {32};
                    variableRow = 1;
                end
                matfield.Layout.setGridItemLayout(layout.VariableLabel, variableRow, 1);
                matfield.Layout.setGridItemLayout(layout.VariableDropDown, variableRow, [2, 3]);
                matfield.Layout.setGridItemLayout(layout.VariableHint, variableRow, 4);
            else
                matfield.Layout.prepareGridColumns(grid, 3);
                grid.ColumnWidth = {82, '1x', 86};
                if layout.ShowFileControl
                    grid.RowHeight = {32, 26, 32, 26};
                    matfield.Layout.setGridItemLayout(layout.FileLabel, 1, 1);
                    matfield.Layout.setGridItemLayout(layout.FilePathEdit, 1, 2);
                    matfield.Layout.setGridItemLayout(layout.BrowseButton, 1, 3);
                    matfield.Layout.setGridItemLayout(layout.FileHint, 2, [2, 3]);
                    variableRow = 3;
                    variableHintRow = 4;
                else
                    grid.RowHeight = {32, 26};
                    variableRow = 1;
                    variableHintRow = 2;
                end
                matfield.Layout.setGridItemLayout(layout.VariableLabel, variableRow, 1);
                matfield.Layout.setGridItemLayout(layout.VariableDropDown, variableRow, [2, 3]);
                matfield.Layout.setGridItemLayout(layout.VariableHint, variableHintRow, [2, 3]);
            end
            matfield.Layout.setLabelWordWrap(layout.FileHint, true);
            matfield.Layout.setLabelWordWrap(layout.VariableHint, true);
            height = sum(cell2mat(grid.RowHeight)) + grid.Padding(2) + ...
                grid.Padding(4) + grid.RowSpacing * (numel(grid.RowHeight) - 1);
        end

        function height = applySliceControlLayout(layout, profile)
            grid = layout.Grid;
            showMode = matfield.Graphics.hasGraphics(layout.ModeDropDown);
            showDimension = matfield.Graphics.hasGraphics(layout.DimensionDropDown);
            showIndex = matfield.Graphics.hasGraphics(layout.IndexSlider);
            showColor = matfield.Graphics.hasGraphics(layout.ColorDropDown);
            showPlayback = matfield.Graphics.hasGraphics(layout.PlayButton);
        
            matfield.Layout.setLabelWordWrap(layout.ModeHint, true);
            matfield.Layout.setLabelWordWrap(layout.PlaybackHint, true);
            switch profile
                case 'wide'
                    matfield.Layout.prepareGridColumns(grid, 14);
                    matfield.Layout.setGridItemLayout(layout.VariableLabel, 1, [1, 3]);
                    matfield.Layout.setGridItemLayout(layout.GlobalLabel, 1, [4, 7]);
                    matfield.Layout.setGridItemLayout(layout.SliceLabel, 1, [8, 14]);
                    matfield.Layout.setGridItemLayout(layout.ModeText, 2, 1);
                    matfield.Layout.setGridItemLayout(layout.ModeDropDown, 2, [2, 4]);
                    matfield.Layout.setGridItemLayout(layout.ModeHint, 2, [5, 14]);
                    matfield.Layout.setGridItemLayout(layout.DimensionText, 3, 1);
                    matfield.Layout.setGridItemLayout(layout.DimensionDropDown, 3, 2);
                    matfield.Layout.setGridItemLayout(layout.IndexText, 3, 3);
                    matfield.Layout.setGridItemLayout(layout.IndexSlider, 3, [4, 6]);
                    matfield.Layout.setGridItemLayout(layout.IndexEdit, 3, 7);
                    matfield.Layout.setGridItemLayout(layout.ColorText, 3, 9);
                    matfield.Layout.setGridItemLayout(layout.ColorDropDown, 3, 10);
                    matfield.Layout.setGridItemLayout(layout.ColorLowerText, 3, 11);
                    matfield.Layout.setGridItemLayout(layout.ColorLowerEdit, 3, 12);
                    matfield.Layout.setGridItemLayout(layout.ColorUpperText, 3, 13);
                    matfield.Layout.setGridItemLayout(layout.ColorUpperEdit, 3, 14);
                    matfield.Layout.setGridItemLayout(layout.ColorLowerSliderText, 4, [1, 2]);
                    matfield.Layout.setGridItemLayout(layout.ColorLowerSlider, 4, [3, 7]);
                    matfield.Layout.setGridItemLayout(layout.ColorUpperSliderText, 4, [8, 9]);
                    matfield.Layout.setGridItemLayout(layout.ColorUpperSlider, 4, [10, 14]);
                    matfield.Layout.setGridItemLayout(layout.PlaybackText, 5, 1);
                    matfield.Layout.setGridItemLayout(layout.PlayButton, 5, 2);
                    matfield.Layout.setGridItemLayout(layout.IntervalText, 5, 3);
                    matfield.Layout.setGridItemLayout(layout.PlaybackIntervalEdit, 5, 4);
                    matfield.Layout.setGridItemLayout(layout.PlaybackHint, 5, [5, 14]);
                    rowHeights = {28, 34 * double(showMode), ...
                        42 * double(showDimension || showIndex || showColor), ...
                        42 * double(showColor), 36 * double(showPlayback)};
                    grid.ColumnWidth = {62, 130, 42, '1x', '1x', '1x', ...
                        72, 16, 72, 120, 34, 80, 34, 80};
                case 'compact'
                    matfield.Layout.prepareGridColumns(grid, 6);
                    row = 1;
                    matfield.Layout.setGridItemLayout(layout.VariableLabel, row, [1, 6]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.GlobalLabel, row, [1, 6]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.SliceLabel, row, [1, 6]); row = row + 1;
                    rowHeights = {28, 28, 28};
                    if showMode
                        matfield.Layout.setGridItemLayout(layout.ModeText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ModeDropDown, row, [2, 3]);
                        matfield.Layout.setGridItemLayout(layout.ModeHint, row, [4, 6]);
                        rowHeights{row} = 44; row = row + 1;
                    end
                    if showDimension || showIndex
                        matfield.Layout.setGridItemLayout(layout.DimensionText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.DimensionDropDown, row, 2);
                        matfield.Layout.setGridItemLayout(layout.IndexText, row, 3);
                        matfield.Layout.setGridItemLayout(layout.IndexSlider, row, [4, 5]);
                        matfield.Layout.setGridItemLayout(layout.IndexEdit, row, 6);
                        rowHeights{row} = 42; row = row + 1;
                    end
                    if showColor
                        matfield.Layout.setGridItemLayout(layout.ColorText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ColorDropDown, row, 2);
                        matfield.Layout.setGridItemLayout(layout.ColorLowerText, row, 3);
                        matfield.Layout.setGridItemLayout(layout.ColorLowerEdit, row, 4);
                        matfield.Layout.setGridItemLayout(layout.ColorUpperText, row, 5);
                        matfield.Layout.setGridItemLayout(layout.ColorUpperEdit, row, 6);
                        rowHeights{row} = 38; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.ColorLowerSliderText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ColorLowerSlider, row, [2, 6]);
                        rowHeights{row} = 42; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.ColorUpperSliderText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ColorUpperSlider, row, [2, 6]);
                        rowHeights{row} = 42; row = row + 1;
                    end
                    if showPlayback
                        matfield.Layout.setGridItemLayout(layout.PlaybackText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.PlayButton, row, 2);
                        matfield.Layout.setGridItemLayout(layout.IntervalText, row, 3);
                        matfield.Layout.setGridItemLayout(layout.PlaybackIntervalEdit, row, 4);
                        matfield.Layout.setGridItemLayout(layout.PlaybackHint, row, [5, 6]);
                        rowHeights{row} = 44;
                    end
                    grid.ColumnWidth = {82, 120, 72, '1x', 72, 86};
                otherwise
                    matfield.Layout.prepareGridColumns(grid, 4);
                    row = 1;
                    matfield.Layout.setGridItemLayout(layout.VariableLabel, row, [1, 4]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.GlobalLabel, row, [1, 4]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.SliceLabel, row, [1, 4]); row = row + 1;
                    rowHeights = {28, 28, 28};
                    if showMode
                        matfield.Layout.setGridItemLayout(layout.ModeText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ModeDropDown, row, [2, 4]);
                        rowHeights{row} = 34; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.ModeHint, row, [1, 4]);
                        rowHeights{row} = 36; row = row + 1;
                    end
                    if showDimension
                        matfield.Layout.setGridItemLayout(layout.DimensionText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.DimensionDropDown, row, [2, 4]);
                        rowHeights{row} = 34; row = row + 1;
                    end
                    if showIndex
                        matfield.Layout.setGridItemLayout(layout.IndexText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.IndexSlider, row, [2, 3]);
                        matfield.Layout.setGridItemLayout(layout.IndexEdit, row, 4);
                        rowHeights{row} = 42; row = row + 1;
                    end
                    if showColor
                        matfield.Layout.setGridItemLayout(layout.ColorText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ColorDropDown, row, [2, 4]);
                        rowHeights{row} = 34; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.ColorLowerText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ColorLowerEdit, row, 2);
                        matfield.Layout.setGridItemLayout(layout.ColorUpperText, row, 3);
                        matfield.Layout.setGridItemLayout(layout.ColorUpperEdit, row, 4);
                        rowHeights{row} = 34; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.ColorLowerSliderText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ColorLowerSlider, row, [2, 4]);
                        rowHeights{row} = 42; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.ColorUpperSliderText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ColorUpperSlider, row, [2, 4]);
                        rowHeights{row} = 42; row = row + 1;
                    end
                    if showPlayback
                        matfield.Layout.setGridItemLayout(layout.PlaybackText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.PlayButton, row, 2);
                        matfield.Layout.setGridItemLayout(layout.IntervalText, row, 3);
                        matfield.Layout.setGridItemLayout(layout.PlaybackIntervalEdit, row, 4);
                        rowHeights{row} = 34; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.PlaybackHint, row, [1, 4]);
                        rowHeights{row} = 36;
                    end
                    grid.ColumnWidth = {82, 120, '1x', 86};
            end
            grid.RowHeight = rowHeights;
            height = matfield.Layout.preferredPanelHeight(grid, rowHeights);
        end

        function height = applyVolumeControlLayout(layout, profile, state)
            grid = layout.Grid;
            showMode = matfield.Graphics.hasGraphics(layout.ModeDropDown);
            showIsoMode = matfield.Graphics.hasGraphics(layout.IsoModeDropDown);
            showCount = matfield.Graphics.hasGraphics(layout.CountSpinner);
            showRange = matfield.Graphics.hasGraphics(layout.LowerEdit);
            showExact = matfield.Graphics.hasGraphics(layout.ExactValueSlider);
            showAlpha = matfield.Graphics.hasGraphics(layout.AlphaSlider);
            showPlayback = matfield.Graphics.hasGraphics(layout.PlayButton) && ...
                strcmp(layout.PlayButton.Visible, 'on');
            isoSelectionMode = 'automatic';
            if isfield(state, 'IsoSelectionMode')
                isoSelectionMode = state.IsoSelectionMode;
            end
            isSingle = strcmp(isoSelectionMode, 'single');
        
            matfield.Layout.setLabelWordWrap(layout.ModeHint, true);
            matfield.Layout.setLabelWordWrap(layout.IsoModeHint, true);
            matfield.Layout.setLabelWordWrap(layout.PlaybackHint, true);
            switch profile
                case 'wide'
                    matfield.Layout.prepareGridColumns(grid, 14);
                    matfield.Layout.setGridItemLayout(layout.VariableLabel, 1, [1, 5]);
                    matfield.Layout.setGridItemLayout(layout.GlobalLabel, 1, [6, 9]);
                    matfield.Layout.setGridItemLayout(layout.SamplingLabel, 1, [10, 14]);
                    matfield.Layout.setGridItemLayout(layout.ModeText, 2, 1);
                    matfield.Layout.setGridItemLayout(layout.ModeDropDown, 2, [2, 4]);
                    matfield.Layout.setGridItemLayout(layout.ModeHint, 2, [5, 14]);
                    matfield.Layout.setGridItemLayout(layout.IsoModeText, 3, 1);
                    matfield.Layout.setGridItemLayout(layout.IsoModeDropDown, 3, [2, 4]);
                    matfield.Layout.setGridItemLayout(layout.IsoModeHint, 3, [5, 14]);
                    matfield.Layout.setGridItemLayout(layout.CountText, 4, 1);
                    matfield.Layout.setGridItemLayout(layout.CountSpinner, 4, 2);
                    matfield.Layout.setGridItemLayout(layout.LowerText, 4, 3);
                    matfield.Layout.setGridItemLayout(layout.LowerEdit, 4, 4);
                    matfield.Layout.setGridItemLayout(layout.UpperText, 4, 5);
                    matfield.Layout.setGridItemLayout(layout.UpperEdit, 4, 6);
                    matfield.Layout.setGridItemLayout(layout.ExactValueText, 4, [1, 2]);
                    matfield.Layout.setGridItemLayout(layout.ExactValueEdit, 4, [3, 4]);
                    if showAlpha
                        matfield.Layout.setGridItemLayout(layout.ExactValueSlider, 4, [5, 10]);
                    else
                        matfield.Layout.setGridItemLayout(layout.ExactValueSlider, 4, [5, 14]);
                    end
                    matfield.Graphics.setVolumeAlphaLayout(layout.AlphaText, layout.AlphaSlider, ...
                        isoSelectionMode);
                    matfield.Layout.setGridItemLayout(layout.PlaybackText, 5, [1, 2]);
                    matfield.Layout.setGridItemLayout(layout.PlayButton, 5, [3, 4]);
                    matfield.Layout.setGridItemLayout(layout.IntervalText, 5, 5);
                    matfield.Layout.setGridItemLayout(layout.PlaybackIntervalEdit, 5, 6);
                    matfield.Layout.setGridItemLayout(layout.PlaybackHint, 5, [7, 14]);
                    rowHeights = {28, 34 * double(showMode), ...
                        36 * double(showIsoMode), ...
                        46 * double(showCount || showRange || showExact || showAlpha), ...
                        36 * double(showPlayback)};
                    grid.ColumnWidth = {82, 62, 76, 62, 76, 62, 55, ...
                        '1x', '1x', '1x', 55, 62, 62, 72};
                case 'compact'
                    matfield.Layout.prepareGridColumns(grid, 6);
                    row = 1;
                    matfield.Layout.setGridItemLayout(layout.VariableLabel, row, [1, 6]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.GlobalLabel, row, [1, 6]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.SamplingLabel, row, [1, 6]); row = row + 1;
                    rowHeights = {28, 28, 28};
                    if showMode
                        matfield.Layout.setGridItemLayout(layout.ModeText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ModeDropDown, row, [2, 3]);
                        matfield.Layout.setGridItemLayout(layout.ModeHint, row, [4, 6]);
                        rowHeights{row} = 44; row = row + 1;
                    end
                    if showIsoMode
                        matfield.Layout.setGridItemLayout(layout.IsoModeText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.IsoModeDropDown, row, [2, 3]);
                        matfield.Layout.setGridItemLayout(layout.IsoModeHint, row, [4, 6]);
                        rowHeights{row} = 44; row = row + 1;
                    end
                    parameterRow = row;
                    matfield.Layout.setGridItemLayout(layout.CountText, parameterRow, 1);
                    matfield.Layout.setGridItemLayout(layout.CountSpinner, parameterRow, 2);
                    matfield.Layout.setGridItemLayout(layout.LowerText, parameterRow, 3);
                    matfield.Layout.setGridItemLayout(layout.LowerEdit, parameterRow, 4);
                    matfield.Layout.setGridItemLayout(layout.UpperText, parameterRow, 5);
                    matfield.Layout.setGridItemLayout(layout.UpperEdit, parameterRow, 6);
                    matfield.Layout.setGridItemLayout(layout.ExactValueText, parameterRow, 1);
                    matfield.Layout.setGridItemLayout(layout.ExactValueEdit, parameterRow, 2);
                    matfield.Layout.setGridItemLayout(layout.ExactValueSlider, parameterRow, [3, 6]);
                    if isSingle && showExact
                        rowHeights{row} = 44; row = row + 1;
                    elseif showCount || showRange
                        rowHeights{row} = 38; row = row + 1;
                    end
                    if showAlpha
                        matfield.Layout.setGridItemLayout(layout.AlphaText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.AlphaSlider, row, [2, 6]);
                        rowHeights{row} = 44; row = row + 1;
                    end
                    if matfield.Graphics.hasGraphics(layout.PlayButton)
                        matfield.Layout.setGridItemLayout(layout.PlaybackText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.PlayButton, row, 2);
                        matfield.Layout.setGridItemLayout(layout.IntervalText, row, 3);
                        matfield.Layout.setGridItemLayout(layout.PlaybackIntervalEdit, row, 4);
                        matfield.Layout.setGridItemLayout(layout.PlaybackHint, row, [5, 6]);
                    end
                    if showPlayback
                        rowHeights{row} = 44;
                    elseif matfield.Graphics.hasGraphics(layout.PlayButton)
                        rowHeights{row} = 0;
                    end
                    grid.ColumnWidth = {92, 86, 76, '1x', 76, 86};
                otherwise
                    matfield.Layout.prepareGridColumns(grid, 4);
                    row = 1;
                    matfield.Layout.setGridItemLayout(layout.VariableLabel, row, [1, 4]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.GlobalLabel, row, [1, 4]); row = row + 1;
                    matfield.Layout.setGridItemLayout(layout.SamplingLabel, row, [1, 4]); row = row + 1;
                    rowHeights = {28, 28, 28};
                    if showMode
                        matfield.Layout.setGridItemLayout(layout.ModeText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.ModeDropDown, row, [2, 4]);
                        rowHeights{row} = 34; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.ModeHint, row, [1, 4]);
                        rowHeights{row} = 36; row = row + 1;
                    end
                    if showIsoMode
                        matfield.Layout.setGridItemLayout(layout.IsoModeText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.IsoModeDropDown, row, [2, 4]);
                        rowHeights{row} = 34; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.IsoModeHint, row, [1, 4]);
                        rowHeights{row} = 36; row = row + 1;
                    end
                    parameterRow = row;
                    matfield.Layout.setGridItemLayout(layout.CountText, parameterRow, 1);
                    matfield.Layout.setGridItemLayout(layout.CountSpinner, parameterRow, 2);
                    matfield.Layout.setGridItemLayout(layout.LowerText, parameterRow, 1);
                    matfield.Layout.setGridItemLayout(layout.LowerEdit, parameterRow, 2);
                    matfield.Layout.setGridItemLayout(layout.UpperText, parameterRow, 3);
                    matfield.Layout.setGridItemLayout(layout.UpperEdit, parameterRow, 4);
                    matfield.Layout.setGridItemLayout(layout.ExactValueText, parameterRow, 1);
                    matfield.Layout.setGridItemLayout(layout.ExactValueEdit, parameterRow, 2);
                    matfield.Layout.setGridItemLayout(layout.ExactValueSlider, parameterRow, [3, 4]);
                    if isSingle && showExact
                        rowHeights{row} = 44; row = row + 1;
                    elseif showCount || showRange
                        if showCount
                            rowHeights{row} = 34; row = row + 1;
                        end
                        if showRange
                            matfield.Layout.setGridItemLayout(layout.LowerText, row, 1);
                            matfield.Layout.setGridItemLayout(layout.LowerEdit, row, 2);
                            matfield.Layout.setGridItemLayout(layout.UpperText, row, 3);
                            matfield.Layout.setGridItemLayout(layout.UpperEdit, row, 4);
                            rowHeights{row} = 34; row = row + 1;
                        end
                    end
                    if showAlpha
                        matfield.Layout.setGridItemLayout(layout.AlphaText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.AlphaSlider, row, [2, 4]);
                        rowHeights{row} = 44; row = row + 1;
                    end
                    if matfield.Graphics.hasGraphics(layout.PlayButton)
                        matfield.Layout.setGridItemLayout(layout.PlaybackText, row, 1);
                        matfield.Layout.setGridItemLayout(layout.PlayButton, row, 2);
                        matfield.Layout.setGridItemLayout(layout.IntervalText, row, 3);
                        matfield.Layout.setGridItemLayout(layout.PlaybackIntervalEdit, row, 4);
                    end
                    if showPlayback
                        rowHeights{row} = 34; row = row + 1;
                        matfield.Layout.setGridItemLayout(layout.PlaybackHint, row, [1, 4]);
                        rowHeights{row} = 36;
                    elseif matfield.Graphics.hasGraphics(layout.PlaybackHint)
                        matfield.Layout.setGridItemLayout(layout.PlaybackHint, row, [1, 4]);
                        rowHeights{row} = 0;
                    end
                    grid.ColumnWidth = {92, 100, '1x', 86};
            end
            grid.RowHeight = rowHeights;
            height = matfield.Layout.preferredPanelHeight(grid, rowHeights);
        end

        function prepareGridColumns(grid, targetColumnCount)
            if numel(grid.ColumnWidth) < targetColumnCount
                grid.ColumnWidth = repmat({'1x'}, 1, targetColumnCount);
            end
        end

        function setGridItemLayout(item, row, column)
            if matfield.Graphics.hasGraphics(item)
                item.Layout.Row = row;
                item.Layout.Column = column;
            end
        end

        function setLabelWordWrap(label, shouldWrap)
            if matfield.Graphics.hasGraphics(label) && isprop(label, 'WordWrap')
                value = 'off';
                if shouldWrap
                    value = 'on';
                end
                label.WordWrap = value;
            end
        end

        function height = preferredPanelHeight(grid, rowHeights)
            height = sum(cell2mat(rowHeights)) + grid.Padding(2) + ...
                grid.Padding(4) + grid.RowSpacing * (numel(rowHeights) - 1) + 26;
        end

        function height = currentGridPanelHeight(grid)
            if isempty(grid) || ~isgraphics(grid)
                height = 120;
                return
            end
            numericHeights = cellfun(@(value) double(value), grid.RowHeight);
            height = matfield.Layout.preferredPanelHeight(grid, num2cell(numericHeights));
        end

        function height = currentSourceSelectorHeight(layout)
            if isempty(layout.Grid) || ~isgraphics(layout.Grid)
                height = 0;
                return
            end
            grid = layout.Grid;
            numericHeights = cellfun(@(value) double(value), grid.RowHeight);
            height = sum(numericHeights) + grid.Padding(2) + grid.Padding(4) + ...
                grid.RowSpacing * (numel(numericHeights) - 1);
        end

    end
end
