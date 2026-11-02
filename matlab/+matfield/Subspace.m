classdef Subspace
    %SUBSPACE Select an N-D source's 2-D/3-D field without inferring axis meaning.
    methods (Static)
        function tf = isRetainedDimensions(value)
            tf = isempty(value) || (isnumeric(value) && isreal(value) && isvector(value) && ...
                any(numel(value) == [2, 3]) && all(isfinite(value)) && ...
                all(value >= 1 & value == fix(value)) && all(diff(value(:)) > 0));
        end

        function tf = isExtraIndices(value)
            tf = isnumeric(value) && isreal(value) && (isempty(value) || ...
                (ismatrix(value) && size(value, 2) == 2 && all(isfinite(value), 'all') && ...
                all(value >= 1 & value == fix(value), 'all') && ...
                numel(unique(value(:, 1))) == size(value, 1)));
        end

        function [retained, indices] = selectShape(dataSize, retained, requestedIndices)
            if ~matfield.Subspace.isRetainedDimensions(retained) || ...
                    ~matfield.Subspace.isExtraIndices(requestedIndices)
                error('visualizeMatField:InvalidSubspace', ...
                    'Use increasing 2/3 RetainedDimensions and unique [dimension index] ExtraIndices pairs.');
            end
            dataSize = double(dataSize(:).');
            if numel(dataSize) <= 3
                if matfield.FieldRules.classifyShape(dataSize) == 0 || ...
                        (~isempty(retained) && ~isequal(retained(:).', 1:numel(dataSize))) || ...
                        ~isempty(requestedIndices)
                    error('visualizeMatField:InvalidSubspace', ...
                        'Extra dimension selection requires an N-D source (N >= 4).');
                end
                retained = 1:numel(dataSize);
                indices = zeros(0, 2);
                return
            end
            if isempty(retained)
                retained = find(dataSize > 1, 3);
            end
            retained = double(retained(:).');
            if ~any(numel(retained) == [2, 3]) || any(retained > numel(dataSize)) || ...
                    any(dataSize(retained) <= 1) || any(dataSize <= 0)
                error('visualizeMatField:InvalidSubspace', ...
                    'Each retained dimension must exist and have length greater than one.');
            end
            extras = setdiff(1:numel(dataSize), retained, 'stable');
            indices = [extras(:), ones(numel(extras), 1)];
            for k = 1:size(requestedIndices, 1)
                d = requestedIndices(k, 1);
                i = requestedIndices(k, 2);
                row = find(extras == d, 1);
                if isempty(row) || i > dataSize(d)
                    error('visualizeMatField:ExtraIndexOutOfRange', ...
                        'Dim %d index %d is outside the extra dimensions or array bounds.', d, i);
                end
                indices(row, 2) = i;
            end
        end

        function [data, opts, globalRange] = prepare(raw, opts, retained, indices)
            if nargin < 3
                retained = opts.RetainedDimensions;
            end
            if nargin < 4
                indices = opts.ExtraIndices;
            end
            matfield.FieldRules.requireSourceArray(raw, opts.Variable);
            originalSize = size(raw);
            [retained, indices] = matfield.Subspace.selectShape(originalSize, retained, indices);
            if ndims(raw) > 3
                selectors = repmat({':'}, 1, ndims(raw));
                for k = 1:size(indices, 1)
                    selectors{indices(k, 1)} = indices(k, 2);
                end
                data = reshape(raw(selectors{:}), originalSize(retained));
                opts.Subspace = struct('RawData', raw, 'OriginalSize', originalSize, ...
                    'RetainedDimensions', retained, 'ExtraIndices', indices);
            else
                data = raw;
                if isfield(opts, 'Subspace')
                    opts = rmfield(opts, 'Subspace');
                end
            end
            opts.AxesDimensions = retained;
            opts.FieldDimension = numel(retained);
            opts.PlotType = matfield.Data.resolvePlotTypeForField(opts, opts.FieldDimension);
            if opts.Specified.Dimension
                localDimension = find(retained == opts.RequestedDimension, 1);
                if isempty(localDimension)
                    error('visualizeMatField:DimensionNotRetained', ...
                        'Dimension must identify a retained original array dimension.');
                end
                opts.Dimension = localDimension;
            elseif opts.FieldDimension == 3
                if isempty(opts.Dimension) || opts.Dimension > 3
                    opts.Dimension = 3;
                end
            else
                opts.Dimension = [];
            end
            if opts.FieldDimension == 3 && opts.Specified.Index
                matfield.Input.validateInitialIndex(opts.Index, opts.Dimension, size(data));
            end
            globalRange = matfield.Data.validateLoadedArray(data, opts);
        end

        function axes = axisDimensions(opts)
            axes = 1:opts.FieldDimension;
            if isfield(opts, 'AxesDimensions')
                axes = opts.AxesDimensions;
            end
        end

        function layout = emptyLayout()
            layout = struct('Panel', gobjects(0), 'Grid', gobjects(0), ...
                'Summary', gobjects(0), 'RetainedEdit', gobjects(0), ...
                'ExtraDimensions', [], 'Edits', gobjects(0), 'Sliders', gobjects(0));
        end

        function layout = createControls(mainGrid, row, opts)
            s = opts.Subspace;
            panel = uipanel(mainGrid, 'Title', '额外维度选择 → 二维/三维子数组');
            panel.Layout.Row = row;
            grid = uigridlayout(panel, [2 + size(s.ExtraIndices, 1), 3]);
            grid.ColumnWidth = {94, 120, '1x'};
            grid.RowHeight = [{32, 32}, repmat({42}, 1, size(s.ExtraIndices, 1))];
            grid.Padding = [10, 16, 10, 8];
            grid.Scrollable = 'on';
            summary = uilabel(grid, 'Text', matfield.Subspace.summary(s), 'WordWrap', 'on');
            summary.Layout.Row = 1;
            summary.Layout.Column = [1, 3];
            label = uilabel(grid, 'Text', '保留维度');
            label.Layout.Row = 2;
            label.Layout.Column = 1;
            edit = uieditfield(grid, 'text', 'Value', strjoin(string(s.RetainedDimensions), ', '));
            edit.Layout.Row = 2;
            edit.Layout.Column = [2, 3];
            edit.Editable = matfield.Subspace.onOff(~opts.Specified.RetainedDimensions);
            edit.Tooltip = '递增的两个或三个原数组维度编号，例如 1, 2, 3 或 2, 4。';
            edits = gobjects(1, size(s.ExtraIndices, 1));
            sliders = edits;
            for k = 1:size(s.ExtraIndices, 1)
                d = s.ExtraIndices(k, 1);
                index = s.ExtraIndices(k, 2);
                limit = s.OriginalSize(d);
                label = uilabel(grid, 'Text', sprintf('Dim %d 索引', d));
                label.Layout.Row = k + 2;
                label.Layout.Column = 1;
                edits(k) = uieditfield(grid, 'numeric', 'Value', index, ...
                    'RoundFractionalValues', 'on', 'Limits', [1, max(2, limit)]);
                edits(k).Layout.Row = k + 2;
                edits(k).Layout.Column = 2;
                sliders(k) = uislider(grid, 'Limits', [1, max(2, limit)], 'Value', index);
                sliders(k).Layout.Row = k + 2;
                sliders(k).Layout.Column = 3;
                matfield.Graphics.configureSliderTicks(sliders(k), limit);
                enabled = limit > 1 && ~ismember(d, opts.ExtraIndices(:, 1));
                edits(k).Enable = matfield.Subspace.onOff(enabled);
                sliders(k).Enable = matfield.Subspace.onOff(enabled);
            end
            layout = struct('Panel', panel, 'Grid', grid, 'Summary', summary, ...
                'RetainedEdit', edit, 'ExtraDimensions', s.ExtraIndices(:, 1).', ...
                'Edits', edits, 'Sliders', sliders);
        end

        function value = onOff(tf)
            if tf
                value = 'on';
            else
                value = 'off';
            end
        end

        function text = summary(s)
            pairs = compose('Dim %d=%d', s.ExtraIndices(:, 1), s.ExtraIndices(:, 2));
            text = sprintf('原始形状 %s；保留 Dim %s；%s。全局范围针对当前子数组。', ...
                mat2str(s.OriginalSize), strjoin(string(s.RetainedDimensions), '/'), strjoin(pairs, ', '));
        end

        function height = applyLayout(layout, profile)
            height = 0;
            if ~matfield.Graphics.hasGraphics(layout.Panel)
                return
            end
            if strcmp(profile, 'wide')
                layout.Grid.ColumnWidth = {94, 120, '1x'};
                layout.Grid.RowHeight{1} = 32;
            else
                layout.Grid.ColumnWidth = {82, 86, '1x'};
                layout.Grid.RowHeight{1} = 54;
            end
            height = min(180, matfield.Layout.currentGridPanelHeight(layout.Grid));
        end

        function wire(fig, layout)
            state = fig.UserData;
            state.SubspaceControls = layout;
            state.LastSubspaceClock = tic;
            fig.UserData = state;
            if ~matfield.Graphics.hasGraphics(layout.Panel)
                return
            end
            layout.RetainedEdit.ValueChangedFcn = @(~, ~) matfield.Subspace.changeRetained(fig);
            for k = 1:numel(layout.ExtraDimensions)
                d = layout.ExtraDimensions(k);
                layout.Edits(k).ValueChangedFcn = @(src, ~) matfield.Subspace.changeIndex(fig, d, src.Value, true);
                layout.Sliders(k).ValueChangingFcn = @(~, evt) matfield.Subspace.changeIndex(fig, d, evt.Value, false);
                layout.Sliders(k).ValueChangedFcn = @(src, ~) matfield.Subspace.changeIndex(fig, d, src.Value, true);
            end
        end

        function changeRetained(fig)
            state = fig.UserData;
            text = strtrim(state.SubspaceControls.RetainedEdit.Value);
            parts = regexp(text, '\s*,\s*', 'split');
            retained = str2double(parts);
            indices = state.Options.Subspace.ExtraIndices;
            indices = indices(~ismember(indices(:, 1), retained), :);
            indices = [indices(~ismember(indices(:, 1), state.Options.ExtraIndices(:, 1)), :); ...
                state.Options.ExtraIndices];
            matfield.Subspace.change(fig, retained, indices);
        end

        function changeIndex(fig, dimension, value, final)
            if ~isvalid(fig)
                return
            end
            matfield.Playback.pauseViewerPlayback(fig);
            state = fig.UserData;
            s = state.Options.Subspace;
            value = min(s.OriginalSize(dimension), max(1, round(double(value))));
            row = find(state.SubspaceControls.ExtraDimensions == dimension, 1);
            state.SubspaceControls.Edits(row).Value = value;
            if ~final && toc(state.LastSubspaceClock) < 0.08
                return
            end
            indices = s.ExtraIndices;
            indices(indices(:, 1) == dimension, 2) = value;
            matfield.Subspace.change(fig, s.RetainedDimensions, indices);
        end

        function change(fig, retained, indices)
            old = fig.UserData;
            matfield.Playback.pauseViewerPlayback(fig);
            opts = old.Options;
            sameAxes = isequal(retained, opts.Subspace.RetainedDimensions);
            try
                if ~sameAxes
                    opts.PlotType = opts.RequestedPlotType;
                    if ~opts.Specified.Dimension, opts.Dimension = []; end
                    if ~opts.Specified.Index, opts.Index = []; end
                end
                [data, opts, range] = matfield.Subspace.prepare(opts.Subspace.RawData, opts, retained, indices);
                if sameAxes
                    state = fig.UserData;
                    state.Data = data;
                    state.Options = opts;
                    state.GlobalRange = range;
                    state.LastSubspaceClock = tic;
                    if strcmp(state.PlotMode, 'slice')
                        state.GlobalClim = matfield.Graphics.makeSafeLimits(range);
                    else
                        if ~isnumeric(opts.ColorLimits)
                            state.ColorLimits = matfield.Graphics.makeSafeLimits(range);
                        end
                        state.ExactIsoValue = min(range(2), max(range(1), state.ExactIsoValue));
                        controls = {state.ExactValueSlider, state.ExactValueEdit};
                        for c = 1:numel(controls)
                            control = controls{c};
                            if isgraphics(control)
                                if isa(control, 'matlab.ui.control.Slider')
                                    control.Limits = [min([range, control.Limits]), max([range, control.Limits])];
                                else
                                    control.Limits = [-Inf, Inf];
                                end
                                control.Value = state.ExactIsoValue;
                                control.Limits = matfield.Graphics.makeSafeLimits(range);
                            end
                        end
                        if isgraphics(state.ExactValueSlider)
                            matfield.Graphics.configureValueSliderTicks(state.ExactValueSlider, range);
                        end
                    end
                    state.Layout.Control.GlobalLabel.Text = sprintf('当前子数组全局 [min, max]：%g / %g', range);
                    if isfield(state, 'LastSubspaceError')
                        state = rmfield(state, 'LastSubspaceError');
                    end
                    fig.UserData = state;
                    matfield.Subspace.restoreControls(fig);
                    if strcmp(state.PlotMode, 'slice')
                        limits = {state.Axes.XLim, state.Axes.YLim};
                        matfield.SliceView.renderSlice(fig, state.Index);
                        state.Axes.XLim = limits{1};
                        state.Axes.YLim = limits{2};
                    else
                        matfield.VolumeView.renderVolume(fig);
                    end
                elseif strcmp(opts.PlotType, 'slice')
                    matfield.SliceView.createSliceFigure(data, opts, range, fig);
                else
                    matfield.VolumeView.createVolumeFigure(data, opts, range, fig);
                end
            catch exception
                if isvalid(fig)
                    matfield.Subspace.restoreControls(fig);
                    state = fig.UserData;
                    state.LastSubspaceError = exception.message;
                    fig.UserData = state;
                    matfield.Viewer.showViewerAlert(fig, exception.message, '无法选择子数组');
                end
            end
        end

        function restoreControls(fig)
            state = fig.UserData;
            s = state.Options.Subspace;
            layout = state.SubspaceControls;
            layout.Summary.Text = matfield.Subspace.summary(s);
            layout.RetainedEdit.Value = strjoin(string(s.RetainedDimensions), ', ');
            for k = 1:size(s.ExtraIndices, 1)
                layout.Edits(k).Value = s.ExtraIndices(k, 2);
                layout.Sliders(k).Value = s.ExtraIndices(k, 2);
            end
        end

        function label = globalRangeLabel(opts, range)
            prefix = '全局';
            if isfield(opts, 'Subspace')
                prefix = '当前子数组全局';
            end
            label = sprintf('%s [min, max]：%s / %s', prefix, ...
                matfield.Graphics.formatNumber(range(1)), matfield.Graphics.formatNumber(range(2)));
        end
    end
end
