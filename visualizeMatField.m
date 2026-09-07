function fig = visualizeMatField(matFile, variablePath, varargin)
%VISUALIZEMATFIELD Interactively inspect a nested 3-D variable in a MAT file.
%
% Basic usage
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'rho.rho_XYZ')
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'T.T_XYZ', ...
%       'PlotType', 'slice', 'Dimension', 'Z', 'Index', 80)
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', ...
%       'rho.gradNorm_XYZ', 'PlotType', 'volume')
%
% Plot types
%   slice  - A single array plane. 'figure' is accepted as an alias. The
%            dimension, index and color scaling remain editable.
%   volume - Multiple translucent isosurfaces (the 3-D counterpart of a
%            contour plot). The number/range/opacity can be edited.
%   The plot type can always be changed from inside the viewer.
%
% Required input
%   matFile           First positional argument: MAT-file path.
%   variablePath      Second positional argument: dot-separated path to a
%                     real numeric 3-D child field.
%
% Defaults
%   plot type         volume
%   slice dimension   3 (Z/K)
%   slice index       center of the selected dimension
%   color limits      global data range
%   isosurfaces       5, spanning 15%%--85%% of the global value range
%
% Optional inputs are Name-Value parameters only
%   PlotType          'volume' (default), 'slice'/'figure', or '3d'
%                     /'isosurface'
%   Dimension         1/2/3, I/J/K, or X/Y/Z
%   Index             Positive integer slice index
%   Colormap          MATLAB colormap name, default 'turbo'
%   ColorLimits       'global', 'slice', or numeric [low high]
%   NumIsosurfaces    Integer in [1, 12], default 5
%   IsoRange          Fractions [low high] in [0, 1], default [0.15 0.85]
%   IsoValues         Exact isosurface values; mutually exclusive with the
%                     NumIsosurfaces and IsoRange parameters
%   SurfaceAlpha      Number in (0, 1], default 0.22
%   MaxRenderSize     Maximum sampled length per volume axis, default 96
%   Visible           'on' or 'off', default 'on' (useful for tests)
%
% Notes
%   Array dimensions are deliberately labelled Dim 1/2/3. This avoids
%   silently assuming that an *_IJK and an *_XYZ variable use identical
%   physical-axis conventions.

    if nargin < 1
        error('visualizeMatField:MatFileRequired', ...
            'The first positional input must be a MAT-file path.');
    end
    if nargin < 2
        error('visualizeMatField:VariableRequired', ...
            ['The second positional input must be a child-variable path, ', ...
             'for example "rho.rho_XYZ".']);
    end

    opts = parseViewerInputs(matFile, variablePath, varargin{:});
    [volumeData, resolvedFile] = loadNestedVolume(opts.MatFile, opts.Variable);

    finiteMask = isfinite(volumeData);
    if ~any(finiteMask, 'all')
        error('visualizeMatField:NoFiniteData', ...
            'Variable "%s" does not contain any finite values.', opts.Variable);
    end
    globalRange = [min(volumeData(finiteMask)), max(volumeData(finiteMask))];
    clear finiteMask

    if opts.Specified.IsoValues && ...
            (any(opts.IsoValues < globalRange(1)) || any(opts.IsoValues > globalRange(2)))
        error('visualizeMatField:IsoValuesOutOfRange', ...
            'Every IsoValues entry must be inside the global data range [%g, %g].', ...
            globalRange(1), globalRange(2));
    end

    opts.MatFile = resolvedFile;
    opts.Dimension = normalizeDimension(opts.Dimension);
    validateInitialIndex(opts.Index, opts.Dimension, size(volumeData));

    switch opts.PlotType
        case 'slice'
            fig = createSliceFigure(volumeData, opts, globalRange);
        case 'volume'
            fig = createVolumeFigure(volumeData, opts, globalRange);
        otherwise
            error('visualizeMatField:InternalPlotType', ...
                'Unsupported normalized plot type "%s".', opts.PlotType);
    end
end


function opts = parseViewerInputs(matFile, variablePath, varargin)
    plotTypeNames = ["slice", "figure", "volume", "3d", "isosurface"];

    if ~isTextScalar(matFile)
        error('visualizeMatField:InvalidMatFile', ...
            'The first positional input matFile must be a character vector or string scalar.');
    end
    if ~isTextScalar(variablePath)
        error('visualizeMatField:InvalidVariable', ...
            'The second positional input variablePath must be a character vector or string scalar.');
    end
    if strcmpi(strtrim(char(matFile)), 'MatFile')
        error('visualizeMatField:RequiredInputsMustBePositional', ...
            ['matFile and variablePath are positional inputs, not Name-Value parameters. ', ...
             'Use visualizeMatField(matFile, variablePath, Name, Value, ...).']);
    end
    if ~isempty(varargin) && isTextScalar(varargin{1}) && ...
            any(lower(string(varargin{1})) == plotTypeNames)
        error('visualizeMatField:PlotTypeMustBeNameValue', ...
            ['PlotType is optional and must use Name-Value syntax. For example: ', ...
             'visualizeMatField(matFile, variablePath, ''PlotType'', ''slice'').']);
    end
    if mod(numel(varargin), 2) ~= 0
        error('visualizeMatField:IncompleteNameValuePair', ...
            'Optional inputs must be complete Name-Value pairs.');
    end

    parser = inputParser;
    parser.FunctionName = mfilename;
    parser.CaseSensitive = false;
    parser.PartialMatching = false;
    addParameter(parser, 'PlotType', 'volume', @isTextScalar);
    addParameter(parser, 'Dimension', [], @isDimensionValue);
    addParameter(parser, 'Index', [], @isIndexValue);
    addParameter(parser, 'Colormap', 'turbo', @isTextScalar);
    addParameter(parser, 'ColorLimits', 'global', @isColorLimitsValue);
    addParameter(parser, 'NumIsosurfaces', 5, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x == fix(x) && x >= 1 && x <= 12);
    addParameter(parser, 'IsoRange', [0.15, 0.85], ...
        @(x) isnumeric(x) && numel(x) == 2 && all(isfinite(x)) && ...
             x(1) >= 0 && x(2) <= 1 && x(1) < x(2));
    addParameter(parser, 'IsoValues', [], @isIsoValuesValue);
    addParameter(parser, 'SurfaceAlpha', 0.22, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 1);
    addParameter(parser, 'MaxRenderSize', 96, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x == fix(x) && x >= 16);
    addParameter(parser, 'Visible', 'on', ...
        @(x) isTextScalar(x) && any(strcmpi(string(x), ["on", "off"])));

    parse(parser, varargin{:});
    usingDefaults = parser.UsingDefaults;
    opts = parser.Results;
    opts.Specified = struct( ...
        'PlotType', ~ismember('PlotType', usingDefaults), ...
        'Dimension', ~ismember('Dimension', usingDefaults), ...
        'Index', ~ismember('Index', usingDefaults), ...
        'ColorLimits', ~ismember('ColorLimits', usingDefaults), ...
        'NumIsosurfaces', ~ismember('NumIsosurfaces', usingDefaults), ...
        'IsoRange', ~ismember('IsoRange', usingDefaults), ...
        'IsoValues', ~ismember('IsoValues', usingDefaults), ...
        'SurfaceAlpha', ~ismember('SurfaceAlpha', usingDefaults), ...
        'MaxRenderSize', ~ismember('MaxRenderSize', usingDefaults));
    opts.MatFile = char(matFile);
    if isempty(strtrim(opts.MatFile))
        error('visualizeMatField:MatFileRequired', ...
            'The first positional input matFile cannot be empty.');
    end
    opts.Variable = char(variablePath);
    if isempty(strtrim(opts.Variable))
        error('visualizeMatField:VariableRequired', ...
            'The second positional input variablePath cannot be empty.');
    end
    opts.PlotType = normalizePlotType(opts.PlotType);
    opts.Colormap = char(opts.Colormap);
    opts.IsoRange = double(opts.IsoRange(:).');
    opts.IsoValues = unique(double(opts.IsoValues(:).'));
    opts.Visible = char(lower(string(opts.Visible)));

    if opts.Specified.Index && ~opts.Specified.Dimension
        error('visualizeMatField:IndexRequiresDimension', ...
            'Index can only be specified when Dimension is also explicitly specified.');
    end
    if (opts.Specified.Dimension || opts.Specified.Index) && ...
            (~opts.Specified.PlotType || ~strcmp(opts.PlotType, 'slice'))
        error('visualizeMatField:SliceOptionRequiresSliceMode', ...
            'Dimension and Index require an explicitly selected slice/figure PlotType.');
    end

    volumeOptionSpecified = opts.Specified.NumIsosurfaces || ...
        opts.Specified.IsoRange || opts.Specified.IsoValues || ...
        opts.Specified.SurfaceAlpha || opts.Specified.MaxRenderSize;
    if volumeOptionSpecified && ...
            (~opts.Specified.PlotType || ~strcmp(opts.PlotType, 'volume'))
        error('visualizeMatField:VolumeOptionRequiresVolumeMode', ...
            ['NumIsosurfaces, IsoRange, IsoValues, SurfaceAlpha and ', ...
             'MaxRenderSize require an explicitly selected volume PlotType.']);
    end
    if opts.Specified.IsoValues && isempty(opts.IsoValues)
        error('visualizeMatField:EmptyIsoValues', ...
            'Explicit IsoValues cannot be empty.');
    end
    if opts.Specified.IsoValues && ...
            (opts.Specified.NumIsosurfaces || opts.Specified.IsoRange)
        error('visualizeMatField:ConflictingIsoOptions', ...
            'IsoValues cannot be combined with NumIsosurfaces or IsoRange.');
    end

    if isTextScalar(opts.ColorLimits)
        opts.ColorLimits = char(lower(string(opts.ColorLimits)));
        if ~any(strcmp(opts.ColorLimits, {'global', 'slice'}))
            error('visualizeMatField:ColorLimits', ...
                'ColorLimits must be ''global'', ''slice'', or a numeric [low high] pair.');
        end
    else
        opts.ColorLimits = double(opts.ColorLimits(:).');
    end
end


function [value, resolvedFile] = loadNestedVolume(matFile, variablePath)
    if isempty(strtrim(matFile))
        error('visualizeMatField:EmptyFile', 'MatFile cannot be empty.');
    end
    if ~isfile(matFile)
        error('visualizeMatField:FileNotFound', ...
            'MAT file was not found: %s', matFile);
    end
    resolvedFile = char(java.io.File(matFile).getCanonicalPath());

    parts = strsplit(strtrim(variablePath), '.');
    if numel(parts) < 2 || any(cellfun(@isempty, parts))
        error('visualizeMatField:VariablePath', ...
            ['Variable must identify a child field with a dot-separated ', ...
             'path such as "rho.rho_XYZ".']);
    end

    rootName = parts{1};
    rootInfo = whos('-file', resolvedFile, rootName);
    if isempty(rootInfo)
        available = whos('-file', resolvedFile);
        availableText = strjoin({available.name}, ', ');
        error('visualizeMatField:RootNotFound', ...
            'Top-level variable "%s" was not found. Available variables: %s', ...
            rootName, availableText);
    end

    % Loading only the requested top-level struct avoids loading every large
    % field family in the MAT file.
    loaded = load(resolvedFile, rootName);
    value = loaded.(rootName);
    traversed = rootName;
    for k = 2:numel(parts)
        fieldName = parts{k};
        if ~isstruct(value) || ~isscalar(value) || ~isfield(value, fieldName)
            if isstruct(value) && isscalar(value)
                children = strjoin(fieldnames(value), ', ');
            else
                children = '<not a scalar struct>';
            end
            error('visualizeMatField:FieldNotFound', ...
                'Cannot resolve "%s" below "%s". Available fields: %s', ...
                fieldName, traversed, children);
        end
        value = value.(fieldName);
        traversed = [traversed, '.', fieldName]; %#ok<AGROW>
    end

    if ~isnumeric(value) || ~isreal(value) || ndims(value) ~= 3
        error('visualizeMatField:NotRealNumeric3D', ...
            'Variable "%s" must be a real numeric 3-D array; got %s %s.', ...
            variablePath, class(value), mat2str(size(value)));
    end
end


function fig = prepareViewerFigure(existingFig, figName, defaultPosition, visible)
    if isempty(existingFig)
        fig = uifigure('Name', figName, 'Position', defaultPosition, ...
            'Color', [0.97, 0.97, 0.98], 'Visible', visible);
    else
        if ~isvalid(existingFig)
            error('visualizeMatField:InvalidFigure', ...
                'The viewer figure was closed before its mode could be changed.');
        end
        fig = existingFig;
        delete(fig.Children);
        fig.Name = figName;
        fig.Color = [0.97, 0.97, 0.98];
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
                createSliceFigure(volumeData, opts, globalRange, fig);
            case 'volume'
                createVolumeFigure(volumeData, opts, globalRange, fig);
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


function fig = createSliceFigure(volumeData, opts, globalRange, existingFig)
    if nargin < 4
        existingFig = [];
    end
    dataSize = size(volumeData);
    dimension = opts.Dimension;
    if isempty(opts.Index)
        index = round((dataSize(dimension) + 1) / 2);
    else
        index = double(opts.Index);
    end
    showModeControl = ~opts.Specified.PlotType;
    showDimensionControl = ~opts.Specified.Dimension;
    showIndexControl = ~opts.Specified.Index;
    showColorControl = ~opts.Specified.ColorLimits;
    showSliceControlRow = showDimensionControl || showIndexControl || showColorControl;

    figName = sprintf('%s | slice', opts.Variable);
    fig = prepareViewerFigure(existingFig, figName, [120, 80, 1120, 800], opts.Visible);
    mainGrid = uigridlayout(fig, [2, 1]);
    mainGrid.RowHeight = {'1x', 84 + 34 * double(showModeControl) + ...
        42 * double(showSliceControlRow)};
    mainGrid.Padding = [12, 12, 12, 12];
    mainGrid.RowSpacing = 8;

    ax = uiaxes(mainGrid);
    ax.Layout.Row = 1;
    ax.Box = 'on';
    ax.FontName = 'Consolas';
    ax.FontSize = 12;
    ax.Toolbar.Visible = 'on';
    colormap(ax, opts.Colormap);
    cb = colorbar(ax);
    cb.Label.String = 'Value';

    controlPanel = uipanel(mainGrid, 'Title', '切片控制', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.98, 0.98, 0.99]);
    controlPanel.Layout.Row = 2;
    controls = uigridlayout(controlPanel, [3, 10]);
    controls.RowHeight = {28, 34 * double(showModeControl), ...
        42 * double(showSliceControlRow)};
    controls.ColumnWidth = {62, 130, 42, '1x', '1x', '1x', 72, 48, 78, 105};
    controls.Padding = [10, 6, 10, 8];
    controls.ColumnSpacing = 7;

    variableLabel = uilabel(controls, ...
        'Text', sprintf('变量：%s', opts.Variable), 'FontWeight', 'bold');
    variableLabel.Layout.Row = 1;
    variableLabel.Layout.Column = [1, 3];
    variableLabel.Tooltip = opts.MatFile;

    globalLabel = uilabel(controls, ...
        'Text', sprintf('全局 [min, max]：%s / %s', ...
        formatNumber(globalRange(1)), formatNumber(globalRange(2))));
    globalLabel.Layout.Row = 1;
    globalLabel.Layout.Column = [4, 5];

    sliceLabel = uilabel(controls, 'Text', '切片 [min, max]：-- / --');
    sliceLabel.Layout.Row = 1;
    sliceLabel.Layout.Column = [6, 10];

    modeDropDown = gobjects(0);
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
        modeHint.Layout.Column = [5, 10];
    end

    dimDropDown = gobjects(0);
    if showDimensionControl
        dimText = uilabel(controls, 'Text', '切片维度');
        dimText.Layout.Row = 3;
        dimText.Layout.Column = 1;
        dimDropDown = uidropdown(controls, ...
            'Items', {'Dim 1 (I/X)', 'Dim 2 (J/Y)', 'Dim 3 (K/Z)'}, ...
            'ItemsData', [1, 2, 3], 'Value', dimension);
        dimDropDown.Layout.Row = 3;
        dimDropDown.Layout.Column = 2;
    end

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
        configureSliderTicks(indexSlider, dataSize(dimension));

        indexEdit = uieditfield(controls, 'numeric', ...
            'Limits', [1, dataSize(dimension)], 'RoundFractionalValues', 'on', ...
            'ValueDisplayFormat', '%.0f', 'Value', index);
        indexEdit.Layout.Row = 3;
        indexEdit.Layout.Column = 7;
    end

    if isnumeric(opts.ColorLimits)
        colorMode = 'custom';
        customClim = makeSafeLimits(opts.ColorLimits);
    else
        colorMode = opts.ColorLimits;
        customClim = [];
    end

    colorDropDown = gobjects(0);
    if showColorControl
        colorText = uilabel(controls, 'Text', '色标');
        colorText.Layout.Row = 3;
        colorText.Layout.Column = 8;
        colorDropDown = uidropdown(controls);
        colorDropDown.Layout.Row = 3;
        colorDropDown.Layout.Column = [9, 10];
        if isnumeric(opts.ColorLimits)
            colorDropDown.Items = {'全局范围', '当前切片', '固定输入范围'};
            colorDropDown.ItemsData = {'global', 'slice', 'custom'};
            colorDropDown.Value = 'custom';
        else
            colorDropDown.Items = {'全局范围', '当前切片'};
            colorDropDown.ItemsData = {'global', 'slice'};
            colorDropDown.Value = opts.ColorLimits;
        end
    end

    state = struct( ...
        'Data', volumeData, ...
        'DataSize', dataSize, ...
        'Variable', opts.Variable, ...
        'PlotMode', 'slice', ...
        'Options', opts, ...
        'Dimension', dimension, ...
        'Index', index, ...
        'GlobalRange', globalRange, ...
        'GlobalClim', makeSafeLimits(globalRange), ...
        'CustomClim', customClim, ...
        'ColorMode', colorMode, ...
        'Axes', ax, ...
        'Colorbar', cb, ...
        'Image', gobjects(0), ...
        'ModeDropDown', modeDropDown, ...
        'DimensionDropDown', dimDropDown, ...
        'IndexSlider', indexSlider, ...
        'IndexEdit', indexEdit, ...
        'ColorDropDown', colorDropDown, ...
        'SliceLabel', sliceLabel);
    fig.UserData = state;

    if ~isempty(modeDropDown) && isgraphics(modeDropDown)
        modeDropDown.ValueChangedFcn = @(source, event) onPlotModeChanged(fig, source, event);
    end
    if ~isempty(dimDropDown) && isgraphics(dimDropDown)
        dimDropDown.ValueChangedFcn = @(source, event) onSliceDimensionChanged(fig, source, event);
    end
    if ~isempty(indexSlider) && isgraphics(indexSlider)
        indexSlider.ValueChangingFcn = @(source, event) onSliceSliderMoving(fig, source, event);
        indexSlider.ValueChangedFcn = @(source, event) onSliceSliderChanged(fig, source, event);
        indexEdit.ValueChangedFcn = @(source, event) onSliceIndexEdited(fig, source, event);
    end
    if ~isempty(colorDropDown) && isgraphics(colorDropDown)
        colorDropDown.ValueChangedFcn = @(source, event) onSliceColorModeChanged(fig, source, event);
    end

    renderSlice(fig, index);
end


function onSliceDimensionChanged(fig, source, ~)
    if ~isvalid(fig)
        return
    end
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
        configureSliderTicks(state.IndexSlider, newLength);
        state.IndexEdit.Limits = [1, newLength];
    end
    fig.UserData = state;
    renderSlice(fig, newIndex);
end


function onSliceSliderMoving(fig, ~, event)
    if isvalid(fig)
        renderSlice(fig, round(event.Value));
    end
end


function onSliceSliderChanged(fig, source, ~)
    if isvalid(fig)
        renderSlice(fig, round(source.Value));
    end
end


function onSliceIndexEdited(fig, source, ~)
    if isvalid(fig)
        renderSlice(fig, round(source.Value));
    end
end


function onSliceColorModeChanged(fig, source, ~)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
    state.ColorMode = source.Value;
    fig.UserData = state;
    renderSlice(fig, state.Index);
end


function renderSlice(fig, requestedIndex)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
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

    % Transpose so that the first remaining array dimension is horizontal
    % and the second is vertical, rather than silently treating matrix rows
    % as a physical X coordinate.
    displayPlane = plane.';
    remainingDims = setdiff(1:3, dimension, 'stable');

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
                state.Axes.CLim = makeSafeLimits(sliceRange);
            else
                state.Axes.CLim = state.GlobalClim;
            end
        case 'custom'
            state.Axes.CLim = state.CustomClim;
    end

    state.Index = index;
    if ~isempty(state.IndexSlider) && isgraphics(state.IndexSlider)
        state.IndexSlider.Value = index;
        state.IndexEdit.Value = index;
    end
    state.SliceLabel.Text = sprintf('切片 [min, max]：%s / %s', ...
        formatNumber(sliceRange(1)), formatNumber(sliceRange(2)));

    title(state.Axes, sprintf('%s  |  Dim %d = %d', ...
        state.Variable, dimension, index), 'Interpreter', 'none');
    xlabel(state.Axes, sprintf('Dim %d index', remainingDims(1)));
    ylabel(state.Axes, sprintf('Dim %d index', remainingDims(2)));
    axis(state.Axes, 'xy');
    axis(state.Axes, 'image');
    state.Axes.XLim = [0.5, size(displayPlane, 2) + 0.5];
    state.Axes.YLim = [0.5, size(displayPlane, 1) + 0.5];
    fig.UserData = state;
    drawnow limitrate
end


function fig = createVolumeFigure(volumeData, opts, globalRange, existingFig)
    if nargin < 4
        existingFig = [];
    end
    showModeControl = ~opts.Specified.PlotType;
    useExactIsoValues = opts.Specified.IsoValues;
    showCountControl = ~useExactIsoValues && ~opts.Specified.NumIsosurfaces;
    showRangeControl = ~useExactIsoValues && ~opts.Specified.IsoRange;
    showAlphaControl = ~opts.Specified.SurfaceAlpha;
    showRedrawButton = showCountControl || showRangeControl;
    showVolumeControlRow = showCountControl || showRangeControl || showAlphaControl;

    figName = sprintf('%s | 3-D isosurfaces', opts.Variable);
    fig = prepareViewerFigure(existingFig, figName, [120, 70, 1180, 830], opts.Visible);
    mainGrid = uigridlayout(fig, [2, 1]);
    mainGrid.RowHeight = {'1x', 84 + 34 * double(showModeControl) + ...
        42 * double(showVolumeControlRow)};
    mainGrid.Padding = [12, 12, 12, 12];
    mainGrid.RowSpacing = 8;

    ax = uiaxes(mainGrid);
    ax.Layout.Row = 1;
    ax.Box = 'on';
    ax.FontName = 'Consolas';
    ax.FontSize = 12;
    ax.Toolbar.Visible = 'on';
    colormap(ax, opts.Colormap);
    cb = colorbar(ax);
    cb.Label.String = 'Value';

    controlPanel = uipanel(mainGrid, 'Title', '三维等值面控制', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.98, 0.98, 0.99]);
    controlPanel.Layout.Row = 2;
    controls = uigridlayout(controlPanel, [3, 12]);
    controls.RowHeight = {28, 34 * double(showModeControl), ...
        42 * double(showVolumeControlRow)};
    controls.ColumnWidth = {58, 62, 76, 62, 76, 62, 55, '1x', '1x', '1x', 72, 72};
    controls.Padding = [10, 6, 10, 8];
    controls.ColumnSpacing = 7;

    variableLabel = uilabel(controls, ...
        'Text', sprintf('变量：%s', opts.Variable), 'FontWeight', 'bold');
    variableLabel.Layout.Row = 1;
    variableLabel.Layout.Column = [1, 5];
    variableLabel.Tooltip = opts.MatFile;

    globalLabel = uilabel(controls, ...
        'Text', sprintf('全局 [min, max]：%s / %s', ...
        formatNumber(globalRange(1)), formatNumber(globalRange(2))));
    globalLabel.Layout.Row = 1;
    globalLabel.Layout.Column = [6, 8];

    sampleIndices = cell(1, 3);
    for dim = 1:3
        sampleIndices{dim} = makeSampleIndices(size(volumeData, dim), opts.MaxRenderSize);
    end
    sampledSize = cellfun(@numel, sampleIndices);
    samplingLabel = uilabel(controls, ...
        'Text', sprintf('绘制采样：%s（统计使用完整数据）', mat2str(sampledSize)));
    samplingLabel.Layout.Row = 1;
    samplingLabel.Layout.Column = [9, 12];

    modeDropDown = gobjects(0);
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
        modeHint.Layout.Column = [5, 12];
    end

    countSpinner = gobjects(0);
    if showCountControl
        countText = uilabel(controls, 'Text', '等值面数');
        countText.Layout.Row = 3;
        countText.Layout.Column = 1;
        countSpinner = uispinner(controls, 'Limits', [1, 12], 'Step', 1, ...
            'RoundFractionalValues', 'on', 'Value', opts.NumIsosurfaces);
        countSpinner.Layout.Row = 3;
        countSpinner.Layout.Column = 2;
    end

    lowerEdit = gobjects(0);
    upperEdit = gobjects(0);
    if showRangeControl
        lowerText = uilabel(controls, 'Text', '范围下限%');
        lowerText.Layout.Row = 3;
        lowerText.Layout.Column = 3;
        lowerEdit = uieditfield(controls, 'numeric', 'Limits', [0, 100], ...
            'ValueDisplayFormat', '%.1f', 'Value', 100 * opts.IsoRange(1));
        lowerEdit.Layout.Row = 3;
        lowerEdit.Layout.Column = 4;

        upperText = uilabel(controls, 'Text', '范围上限%');
        upperText.Layout.Row = 3;
        upperText.Layout.Column = 5;
        upperEdit = uieditfield(controls, 'numeric', 'Limits', [0, 100], ...
            'ValueDisplayFormat', '%.1f', 'Value', 100 * opts.IsoRange(2));
        upperEdit.Layout.Row = 3;
        upperEdit.Layout.Column = 6;
    end

    alphaSlider = gobjects(0);
    if showAlphaControl
        alphaText = uilabel(controls, 'Text', '透明度');
        alphaText.Layout.Row = 3;
        alphaText.Layout.Column = 7;
        alphaSlider = uislider(controls, 'Limits', [0.03, 1], ...
            'Value', opts.SurfaceAlpha, 'MajorTicks', [0.05, 0.25, 0.5, 0.75, 1]);
        alphaSlider.Layout.Row = 3;
        alphaSlider.Layout.Column = [8, 10];
    end

    redrawButton = gobjects(0);
    if showRedrawButton
        redrawButton = uibutton(controls, 'push', 'Text', '重新绘制', ...
            'FontWeight', 'bold');
        redrawButton.Layout.Row = 3;
        redrawButton.Layout.Column = [11, 12];
    end

    if isnumeric(opts.ColorLimits)
        volumeClim = makeSafeLimits(opts.ColorLimits);
    else
        volumeClim = makeSafeLimits(globalRange);
    end

    state = struct( ...
        'Data', volumeData, ...
        'Variable', opts.Variable, ...
        'PlotMode', 'volume', ...
        'Options', opts, ...
        'GlobalRange', globalRange, ...
        'ColorLimits', volumeClim, ...
        'NumIsosurfaces', opts.NumIsosurfaces, ...
        'IsoRange', opts.IsoRange, ...
        'IsoValues', opts.IsoValues, ...
        'SurfaceAlpha', opts.SurfaceAlpha, ...
        'Axes', ax, ...
        'Colorbar', cb, ...
        'SampleIndices', {sampleIndices}, ...
        'ModeDropDown', modeDropDown, ...
        'CountSpinner', countSpinner, ...
        'LowerEdit', lowerEdit, ...
        'UpperEdit', upperEdit, ...
        'AlphaSlider', alphaSlider, ...
        'RedrawButton', redrawButton, ...
        'Patches', gobjects(0));
    fig.UserData = state;

    if ~isempty(modeDropDown) && isgraphics(modeDropDown)
        modeDropDown.ValueChangedFcn = @(source, event) onPlotModeChanged(fig, source, event);
    end
    if ~isempty(redrawButton) && isgraphics(redrawButton)
        redrawButton.ButtonPushedFcn = @(source, event) redrawVolume(fig, source, event);
    end
    if ~isempty(alphaSlider) && isgraphics(alphaSlider)
        alphaSlider.ValueChangingFcn = @(source, event) changeSurfaceAlpha(fig, event.Value);
        alphaSlider.ValueChangedFcn = @(source, event) changeSurfaceAlpha(fig, source.Value);
    end

    renderVolume(fig);
end


function redrawVolume(fig, ~, ~)
    if isvalid(fig)
        renderVolume(fig);
    end
end


function changeSurfaceAlpha(fig, alphaValue)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
    validPatches = state.Patches(isgraphics(state.Patches));
    if ~isempty(validPatches)
        set(validPatches, 'FaceAlpha', alphaValue);
    end
    state.SurfaceAlpha = alphaValue;
    if ~isempty(state.AlphaSlider) && isgraphics(state.AlphaSlider)
        state.AlphaSlider.Value = alphaValue;
    end
    fig.UserData = state;
    drawnow limitrate
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

    valueSpan = diff(state.GlobalRange);
    cla(state.Axes);
    hold(state.Axes, 'on');
    state.Axes.CLim = state.ColorLimits;

    if valueSpan == 0
        text(state.Axes, 0.5, 0.5, 0.5, ...
            sprintf('常量场：%s', formatNumber(state.GlobalRange(1))), ...
            'HorizontalAlignment', 'center', 'FontSize', 14);
        levels = state.GlobalRange(1);
        patches = gobjects(0);
    else
        if ~isempty(state.IsoValues)
            levels = state.IsoValues;
        else
            levelBounds = state.GlobalRange(1) + valueSpan * isoRange;
            levels = linspace(levelBounds(1), levelBounds(2), count);
        end

        iIndices = state.SampleIndices{1};
        jIndices = state.SampleIndices{2};
        kIndices = state.SampleIndices{3};
        sampled = state.Data(iIndices, jIndices, kIndices);
        sampled(~isfinite(sampled)) = NaN;

        % Permuting [I J K] -> [J I K] makes MATLAB's meshgrid X/Y/Z
        % coordinates correspond to array dimensions 1/2/3 respectively.
        sampledForPlot = permute(sampled, [2, 1, 3]);
        [coord1, coord2, coord3] = meshgrid(iIndices, jIndices, kIndices);
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

    delete(findall(state.Axes, 'Type', 'light'));
    if ~isempty(patches)
        camlight(state.Axes, 'headlight');
        lighting(state.Axes, 'gouraud');
    end
    hold(state.Axes, 'off');
    grid(state.Axes, 'on');
    box(state.Axes, 'on');
    axis(state.Axes, 'tight');
    axis(state.Axes, 'vis3d');
    daspect(state.Axes, [1, 1, 1]);
    view(state.Axes, 42, 26);
    xlabel(state.Axes, 'Dim 1 index');
    ylabel(state.Axes, 'Dim 2 index');
    zlabel(state.Axes, 'Dim 3 index');
    title(state.Axes, sprintf('%s  |  %d isosurfaces: %s ... %s', ...
        state.Variable, numel(patches), formatNumber(levels(1)), ...
        formatNumber(levels(end))), 'Interpreter', 'none');

    state.NumIsosurfaces = count;
    state.IsoRange = isoRange;
    state.SurfaceAlpha = surfaceAlpha;
    state.Patches = patches;
    fig.UserData = state;
    drawnow
end


function configureSliderTicks(slider, axisLength)
    slider.MajorTicks = unique(round(linspace(1, axisLength, min(5, axisLength))));
    slider.MinorTicks = [];
end


function indices = makeSampleIndices(axisLength, maximumLength)
    step = max(1, ceil(axisLength / maximumLength));
    indices = 1:step:axisLength;
    if indices(end) ~= axisLength
        indices(end + 1) = axisLength;
    end
end


function limits = makeSafeLimits(limits)
    limits = double(limits(:).');
    if numel(limits) ~= 2 || any(~isfinite(limits)) || limits(1) > limits(2)
        error('visualizeMatField:InvalidLimits', ...
            'Color limits must be a finite [low high] pair with low <= high.');
    end
    if limits(1) == limits(2)
        padding = max(abs(limits(1)) * 1e-6, 1e-9);
        limits = limits + [-padding, padding];
    end
end


function dimension = normalizeDimension(dimension)
    if isempty(dimension)
        dimension = 3;
        return
    end
    if isnumeric(dimension)
        dimension = double(dimension);
        return
    end
    switch upper(char(string(dimension)))
        case {'1', 'I', 'X'}
            dimension = 1;
        case {'2', 'J', 'Y'}
            dimension = 2;
        case {'3', 'K', 'Z'}
            dimension = 3;
        otherwise
            error('visualizeMatField:Dimension', ...
                'Dimension must be 1/2/3 or I/J/K or X/Y/Z.');
    end
end


function validateInitialIndex(index, dimension, dataSize)
    if isempty(index)
        return
    end
    if index < 1 || index > dataSize(dimension)
        error('visualizeMatField:IndexOutOfRange', ...
            'Index %d is outside dimension %d range [1, %d].', ...
            index, dimension, dataSize(dimension));
    end
end


function plotType = normalizePlotType(plotType)
    switch lower(char(string(plotType)))
        case {'slice', 'figure'}
            plotType = 'slice';
        case {'volume', '3d', 'isosurface'}
            plotType = 'volume';
        otherwise
            error('visualizeMatField:PlotType', ...
                ['PlotType must be ''slice''/''figure'' or ', ...
                 '''volume''/''3d''/''isosurface''.']);
    end
end


function tf = isTextScalar(value)
    tf = (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value));
end


function tf = isDimensionValue(value)
    tf = isempty(value) || ...
        (isnumeric(value) && isscalar(value) && isfinite(value) && ...
         value == fix(value) && value >= 1 && value <= 3) || ...
        isTextScalar(value);
end


function tf = isIndexValue(value)
    tf = isempty(value) || ...
        (isnumeric(value) && isscalar(value) && isfinite(value) && ...
         value == fix(value) && value >= 1);
end


function tf = isColorLimitsValue(value)
    tf = isTextScalar(value) || ...
        (isnumeric(value) && numel(value) == 2 && all(isfinite(value)) && value(1) <= value(2));
end


function tf = isIsoValuesValue(value)
    tf = isempty(value) || ...
        (isnumeric(value) && isvector(value) && all(isfinite(value)));
end


function textValue = formatNumber(value)
    if isnan(value)
        textValue = 'NaN';
    elseif isinf(value)
        textValue = char(string(value));
    else
        textValue = sprintf('%.6g', value);
    end
end
