function fig = visualizeMatField(varargin)
%VISUALIZEMATFIELD Interactively inspect a 2-D or 3-D numeric MAT variable.
%
% Basic usage
%   visualizeMatField()
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat')
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'rho.rho_XYZ')
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'T.T_XYZ', ...
%       'PlotType', 'slice', 'Dimension', 3, 'Index', 80)
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', ...
%       'rho.gradNorm_XYZ', 'PlotType', 'volume')
%
% Plot types
%   slice  - A single array plane. 'figure' is accepted as an alias. The
%            dimension, index and color scaling remain editable.
%   volume - Multiple translucent isosurfaces (the 3-D counterpart of a
%            contour plot). The number/range/opacity can be edited.
%   If PlotType is omitted, it can be changed from inside the viewer.
%
% Positional input
%   matFile           Optional first positional argument: MAT-file path. If
%                     omitted, enter a path or browse for a file in the UI.
%   variablePath      Optional second positional argument: dot-separated
%                     path to a real numeric 2-D/3-D array. Top-level and
%                     arbitrarily nested scalar-struct fields are accepted.
%                     If omitted, the figure first asks the user to select one.
%
% Defaults
%   plot type         volume
%   slice dimension   3
%   slice index       center of the selected dimension
%   color limits      global data range
%   isosurfaces       5, spanning 15%%--85%% of the global value range
%
% Optional inputs are Name-Value parameters only
%   PlotType          'volume' (default), 'slice'/'figure', or '3d'
%                     /'isosurface'
%   Dimension         Numeric scalar 1, 2, or 3
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
%   Array dimensions are deliberately labelled Dim 1/2/3. The viewer does
%   not infer any physical meaning or coordinate convention for an axis.
%   Volume mode provides rotate, pan, zoom-in, zoom-out and restore-view
%   tools in the UIAxes hover toolbar. Default 3-D mouse interactions are
%   also enabled.

    [matFile, matFileSpecified, variablePath, variableSpecified, ...
        optionalInputs] = splitViewerInputs(varargin);
    opts = parseViewerInputs(matFile, matFileSpecified, variablePath, ...
        variableSpecified, optionalInputs{:});
    if matFileSpecified
        opts.MatFile = resolveMatFile(opts.MatFile);
    end

    if ~variableSpecified
        variableInfo = emptyVariableInfo();
        if matFileSpecified
            variableInfo = listSelectableVariables(opts.MatFile, opts);
        end
        opts.AvailableVariables = {variableInfo.Path};
        opts.AvailableVariableInfo = variableInfo;
        if matFileSpecified && isempty(opts.AvailableVariables)
            error('visualizeMatField:NoSelectableVariables', ...
                ['The MAT file contains no compatible real numeric 2-D/3-D ', ...
                 'arrays for the requested plotting options.']);
        end
        fig = createVariableSelectionFigure(opts);
        return
    end

    [fieldData, resolvedFile, fieldDimension] = ...
        loadTargetArray(opts.MatFile, opts.Variable);
    opts.FieldDimension = fieldDimension;
    opts.PlotType = resolvePlotTypeForField(opts, fieldDimension);
    globalRange = validateLoadedArray(fieldData, opts);

    opts.MatFile = resolvedFile;
    if fieldDimension == 3
        opts.Dimension = normalizeDimension(opts.Dimension);
        validateInitialIndex(opts.Index, opts.Dimension, size(fieldData));
    end

    switch opts.PlotType
        case 'slice'
            fig = createSliceFigure(fieldData, opts, globalRange);
        case 'volume'
            fig = createVolumeFigure(fieldData, opts, globalRange);
        otherwise
            error('visualizeMatField:InternalPlotType', ...
                'Unsupported normalized plot type "%s".', opts.PlotType);
    end
end


function [matFile, matFileSpecified, variablePath, variableSpecified, ...
        optionalInputs] = splitViewerInputs(inputs)
    optionNames = ["PlotType", "Dimension", "Index", "Colormap", ...
        "ColorLimits", "NumIsosurfaces", "IsoRange", "IsoValues", ...
        "SurfaceAlpha", "MaxRenderSize", "Visible"];
    matFile = '';
    matFileSpecified = false;
    variablePath = '';
    variableSpecified = false;
    optionalInputs = inputs;
    if isempty(inputs)
        return
    end

    firstInput = inputs{1};
    if isempty(firstInput)
        optionalInputs = inputs(2:end);
    elseif isTextScalar(firstInput) && ...
            any(strcmpi(string(firstInput), optionNames))
        % The optional Name-Value list starts without positional inputs.
    else
        matFile = firstInput;
        matFileSpecified = true;
        optionalInputs = inputs(2:end);
    end

    if ~matFileSpecified || isempty(optionalInputs)
        return
    end
    firstInput = optionalInputs{1};
    if isempty(firstInput)
        optionalInputs = optionalInputs(2:end);
    elseif isTextScalar(firstInput) && ...
            any(strcmpi(string(firstInput), optionNames))
        % The optional Name-Value list starts immediately after matFile.
    else
        variablePath = firstInput;
        variableSpecified = true;
        optionalInputs = optionalInputs(2:end);
    end
end


function opts = parseViewerInputs(matFile, matFileSpecified, variablePath, ...
        variableSpecified, varargin)
    plotTypeNames = ["slice", "figure", "volume", "3d", "isosurface"];

    if matFileSpecified && ~isTextScalar(matFile)
        error('visualizeMatField:InvalidMatFile', ...
            'The first positional input matFile must be a character vector or string scalar.');
    end
    if variableSpecified && ~isTextScalar(variablePath)
        error('visualizeMatField:InvalidVariable', ...
            'The second positional input variablePath must be a character vector or string scalar.');
    end
    if matFileSpecified && strcmpi(strtrim(char(matFile)), 'MatFile')
        error('visualizeMatField:RequiredInputsMustBePositional', ...
            ['matFile and variablePath are optional positional inputs, not ', ...
             'Name-Value parameters. Use visualizeMatField([matFile], ', ...
             '[variablePath], Name, Value, ...).']);
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
        'MatFile', matFileSpecified, ...
        'Variable', variableSpecified, ...
        'PlotType', ~ismember('PlotType', usingDefaults), ...
        'Dimension', ~ismember('Dimension', usingDefaults), ...
        'Index', ~ismember('Index', usingDefaults), ...
        'ColorLimits', ~ismember('ColorLimits', usingDefaults), ...
        'NumIsosurfaces', ~ismember('NumIsosurfaces', usingDefaults), ...
        'IsoRange', ~ismember('IsoRange', usingDefaults), ...
        'IsoValues', ~ismember('IsoValues', usingDefaults), ...
        'SurfaceAlpha', ~ismember('SurfaceAlpha', usingDefaults), ...
        'MaxRenderSize', ~ismember('MaxRenderSize', usingDefaults));
    if matFileSpecified
        opts.MatFile = char(matFile);
    else
        opts.MatFile = '';
    end
    opts.Variable = char(string(variablePath));
    if variableSpecified && isempty(strtrim(opts.Variable))
        error('visualizeMatField:VariableRequired', ...
            'The second positional input variablePath cannot be empty.');
    end
    opts.PlotType = normalizePlotType(opts.PlotType);
    opts.RequestedPlotType = opts.PlotType;
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


function resolvedFile = resolveMatFile(matFile)
    candidate = strtrim(char(matFile));
    if isempty(candidate)
        error('visualizeMatField:EmptyFile', 'MatFile cannot be empty.');
    end
    fileObject = java.io.File(candidate);
    if ~fileObject.isAbsolute()
        % MATLAB file functions resolve relative paths against MATLAB's
        % current folder, which can differ from the JVM working directory.
        candidate = fullfile(pwd, candidate);
        fileObject = java.io.File(candidate);
    end
    if ~isfile(candidate)
        error('visualizeMatField:FileNotFound', ...
            'MAT file was not found: %s', matFile);
    end
    resolvedFile = char(fileObject.getCanonicalPath());
end


function variableInfo = listSelectableVariables(matFile, opts)
    variableInfo = emptyVariableInfo();

    % Version 7.3 MAT files are HDF5 containers. Walk group/dataset
    % metadata recursively so large arrays are not loaded just to build the
    % selector. MATLAB's internal #refs# storage is deliberately skipped.
    try
        fileInfo = h5info(matFile);
        variableInfo = collectHdf5Variables(fileInfo, variableInfo);
    catch
        % Earlier MAT formats are not HDF5. Top-level numeric arrays can be
        % classified from WHOS metadata; scalar structs are then loaded one
        % at a time and recursively inspected.
        topInfo = whos('-file', matFile);
        for rootIndex = 1:numel(topInfo)
            item = topInfo(rootIndex);
            if isNumericClassName(item.class)
                isComplex = isfield(item, 'complex') && item.complex;
                dimension = classifyTargetShape(item.size);
                if ~isComplex && dimension > 0
                    variableInfo(end + 1) = makeVariableInfo( ...
                        item.name, item.size, dimension); %#ok<AGROW>
                end
            elseif strcmp(item.class, 'struct') && isequal(item.size, [1, 1])
                loaded = load(matFile, item.name);
                variableInfo = collectClassicVariables(loaded.(item.name), ...
                    item.name, variableInfo);
                clear loaded
            end
        end
    end

    if requiresThreeDimensions(opts)
        variableInfo = variableInfo([variableInfo.Dimension] == 3);
    end
    if ~isempty(variableInfo)
        [~, order] = sort({variableInfo.Path});
        variableInfo = variableInfo(order);
    end
end


function info = collectHdf5Variables(group, info)
    if startsWith(group.Name, '/#refs#')
        return
    end
    if ~strcmp(group.Name, '/') && ...
            ~strcmp(hdf5AttributeText(group.Attributes, 'MATLAB_class'), 'struct')
        % Only scalar-struct groups form valid dot-separated MATLAB paths.
        % This prevents datasets internal to objects/tables from appearing
        % as selectable arrays merely because their HDF5 storage is numeric.
        return
    end

    groupPath = regexprep(group.Name, '^/', '');
    groupPath = strrep(groupPath, '/', '.');
    for datasetIndex = 1:numel(group.Datasets)
        dataset = group.Datasets(datasetIndex);
        matlabClass = hdf5AttributeText(dataset.Attributes, 'MATLAB_class');
        if ~isNumericClassName(matlabClass) || ...
                ~any(strcmp(dataset.Datatype.Class, {'H5T_FLOAT', 'H5T_INTEGER'}))
            continue
        end
        dimension = classifyTargetShape(dataset.Dataspace.Size);
        if dimension == 0
            continue
        end
        if isempty(groupPath)
            path = dataset.Name;
        else
            path = [groupPath, '.', dataset.Name];
        end
        info(end + 1) = makeVariableInfo( ...
            path, dataset.Dataspace.Size, dimension); %#ok<AGROW>
    end

    for groupIndex = 1:numel(group.Groups)
        info = collectHdf5Variables(group.Groups(groupIndex), info);
    end
end


function info = collectClassicVariables(value, path, info)
    if isnumeric(value)
        dimension = classifyTargetArray(value);
        if dimension > 0
            info(end + 1) = makeVariableInfo(path, size(value), dimension);
        end
        return
    end
    if ~isstruct(value) || ~isscalar(value)
        return
    end

    fields = fieldnames(value);
    for fieldIndex = 1:numel(fields)
        field = fields{fieldIndex};
        info = collectClassicVariables(value.(field), ...
            [path, '.', field], info);
    end
end


function text = hdf5AttributeText(attributes, attributeName)
    text = '';
    for attributeIndex = 1:numel(attributes)
        if strcmp(attributes(attributeIndex).Name, attributeName)
            value = attributes(attributeIndex).Value;
            if isnumeric(value)
                text = char(value(:).');
            else
                text = char(string(value));
            end
            return
        end
    end
end


function info = emptyVariableInfo()
    info = struct('Path', {}, 'Size', {}, 'Dimension', {});
end


function info = makeVariableInfo(path, dataSize, dimension)
    info = struct('Path', char(path), ...
        'Size', double(dataSize(:).'), 'Dimension', dimension);
end


function tf = requiresThreeDimensions(opts)
    volumeOptionsSpecified = opts.Specified.NumIsosurfaces || ...
        opts.Specified.IsoRange || opts.Specified.IsoValues || ...
        opts.Specified.SurfaceAlpha || opts.Specified.MaxRenderSize;
    tf = (opts.Specified.PlotType && strcmp(opts.PlotType, 'volume')) || ...
        opts.Specified.Dimension || opts.Specified.Index || volumeOptionsSpecified;
end


function dimension = classifyTargetArray(value)
    dimension = 0;
    if isnumeric(value) && isreal(value)
        dimension = classifyTargetShape(size(value));
    end
end


function dimension = classifyTargetShape(dataSize)
    dataSize = double(dataSize(:).');
    while numel(dataSize) > 2 && dataSize(end) == 1
        dataSize(end) = [];
    end
    if numel(dataSize) == 2 && all(dataSize > 1)
        dimension = 2;
    elseif numel(dataSize) == 3 && all(dataSize > 1)
        dimension = 3;
    else
        dimension = 0;
    end
end


function tf = isNumericClassName(className)
    numericClasses = {'double', 'single', 'int8', 'uint8', 'int16', ...
        'uint16', 'int32', 'uint32', 'int64', 'uint64'};
    tf = any(strcmp(char(className), numericClasses));
end


function plotType = resolvePlotTypeForField(opts, fieldDimension)
    if fieldDimension == 3
        plotType = opts.PlotType;
        return
    end
    if opts.Specified.PlotType && strcmp(opts.PlotType, 'volume')
        error('visualizeMatField:VolumeRequires3D', ...
            'PlotType ''volume'' requires a real numeric 3-D array.');
    end
    if opts.Specified.Dimension || opts.Specified.Index
        error('visualizeMatField:SlicePlaneRequires3D', ...
            ['Dimension and Index select a plane from a 3-D array and ', ...
             'cannot be used with a 2-D array.']);
    end
    plotType = 'slice';
end


function globalRange = validateLoadedArray(fieldData, opts)
    finiteMask = isfinite(fieldData);
    if ~any(finiteMask, 'all')
        error('visualizeMatField:NoFiniteData', ...
            'Variable "%s" does not contain any finite values.', opts.Variable);
    end
    % UI numeric properties require double values. Convert only these two
    % statistics; keep the potentially very large field in its source type.
    globalRange = double([min(fieldData(finiteMask)), max(fieldData(finiteMask))]);

    if opts.Specified.IsoValues && ...
            (any(opts.IsoValues < globalRange(1)) || ...
             any(opts.IsoValues > globalRange(2)))
        error('visualizeMatField:IsoValuesOutOfRange', ...
            'Every IsoValues entry must be inside the global data range [%g, %g].', ...
            globalRange(1), globalRange(2));
    end
end


function [value, resolvedFile, fieldDimension] = loadTargetArray(matFile, variablePath)
    resolvedFile = resolveMatFile(matFile);

    parts = strsplit(strtrim(variablePath), '.');
    if any(cellfun(@isempty, parts))
        error('visualizeMatField:VariablePath', ...
            ['Variable must identify a top-level array or a dot-separated ', ...
             'scalar-struct field such as "rho.rho_XYZ".']);
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

    fieldDimension = classifyTargetArray(value);
    if fieldDimension == 0
        error('visualizeMatField:NotTargetArray', ...
            ['Variable "%s" must be a real numeric 2-D matrix or a real ', ...
             'numeric 3-D array; got %s %s.'], ...
            variablePath, class(value), mat2str(size(value)));
    end
end


function fig = prepareViewerFigure(existingFig, figName, defaultPosition, visible)
    if isempty(existingFig)
        fig = uifigure('Name', figName, 'Position', defaultPosition, ...
            'Color', [0.97, 0.97, 0.98], 'Visible', visible, ...
            'ToolBar', 'figure', ...
            'CloseRequestFcn', @(source, event) closeViewerFigure(source, event));
    else
        if ~isvalid(existingFig)
            error('visualizeMatField:InvalidFigure', ...
                'The viewer figure was closed before its mode could be changed.');
        end
        fig = existingFig;
        stopViewerPlayback(fig, true);
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


function [filePathEdit, browseButton, variableDropDown] = ...
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
    onMatFilePathChanged(fig, state.FilePathEdit, []);
end


function onMatFilePathChanged(fig, source, ~)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
    opts = state.Options;
    enteredPath = strtrim(source.Value);
    if isempty(enteredPath)
        showViewerAlert(fig, '请输入 MAT 文件路径，或使用“浏览…”按钮选择文件。', ...
            '尚未指定 MAT 文件');
        return
    end

    source.Enable = 'off';
    fig.Pointer = 'watch';
    drawnow
    try
        resolvedFile = resolveMatFile(enteredPath);
        opts.MatFile = resolvedFile;
        opts.Variable = '';
        opts.PlotType = opts.RequestedPlotType;
        variableInfo = listSelectableVariables(resolvedFile, opts);
        opts.AvailableVariables = {variableInfo.Path};
        opts.AvailableVariableInfo = variableInfo;
        createVariableSelectionFigure(opts, fig);
        fig.Pointer = 'arrow';
        drawnow
        if isempty(variableInfo)
            showViewerAlert(fig, ...
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
        showViewerAlert(fig, exception.message, '无法打开 MAT 文件');
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
                42 * double(showControlRow) + 36 * double(showIndex);
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

    if isempty(opts.MatFile)
        figName = '请选择 MAT 文件';
    end

    fig = prepareViewerFigure(existingFig, figName, ...
        [120, 70, 1180, 830], opts.Visible);
    mainGrid = uigridlayout(fig, [3, 1]);
    mainGrid.RowHeight = {sourceSelectorHeight(opts), '1x', panelHeight};
    mainGrid.Padding = [18, 18, 18, 18];
    mainGrid.RowSpacing = 8;
    [filePathEdit, browseButton, variableDropDown] = ...
        addSourceSelector(mainGrid, opts, '');

    ax = uiaxes(mainGrid);
    ax.Layout.Row = 2;
    ax.Visible = 'off';
    ax.Toolbar.Visible = 'off';

    controlPanel = uipanel(mainGrid, 'Title', panelTitle, ...
        'FontWeight', 'bold', 'BackgroundColor', [0.98, 0.98, 0.99]);
    controlPanel.Layout.Row = 3;
    switch opts.PlotType
        case 'slice'
            createDisabledSliceControls(controlPanel, opts);
        case 'volume'
            createDisabledVolumeControls(controlPanel, opts);
    end

    fig.UserData = struct( ...
        'MatFile', opts.MatFile, ...
        'Variable', '', ...
        'PlotMode', opts.PlotType, ...
        'Options', opts, ...
        'Axes', ax, ...
        'FilePathEdit', filePathEdit, ...
        'BrowseButton', browseButton, ...
        'VariableDropDown', variableDropDown, ...
        'PlayButton', gobjects(0), ...
        'PlaybackTimer', []);
    variableDropDown.ValueChangedFcn = ...
        @(source, event) onVariableChanged(fig, source, event);
    if ~isempty(filePathEdit) && isgraphics(filePathEdit)
        filePathEdit.ValueChangedFcn = ...
            @(source, event) onMatFilePathChanged(fig, source, event);
        browseButton.ButtonPushedFcn = ...
            @(source, event) browseForMatFile(fig, source, event);
    end
end


function createDisabledSliceControls(controlPanel, opts)
    showMode = ~opts.Specified.PlotType;
    showDimension = ~opts.Specified.Dimension;
    showIndex = ~opts.Specified.Index;
    showColor = ~opts.Specified.ColorLimits;
    showControlRow = showDimension || showIndex || showColor;

    controls = uigridlayout(controlPanel, [4, 10]);
    controls.RowHeight = {28, 34 * double(showMode), ...
        42 * double(showControlRow), 36 * double(showIndex)};
    controls.ColumnWidth = {62, 130, 42, '1x', '1x', '1x', 72, 24, 60, 145};
    controls.Padding = [10, 14, 10, 8];
    controls.ColumnSpacing = 7;
    controls.RowSpacing = 6;

    pending = uilabel(controls, 'Text', '变量：尚未选择', 'FontWeight', 'bold');
    pending.Layout.Row = 1;
    pending.Layout.Column = [1, 3];
    globalLabel = uilabel(controls, 'Text', '全局 [min, max]：-- / --');
    globalLabel.Layout.Row = 1;
    globalLabel.Layout.Column = [4, 5];
    sliceLabel = uilabel(controls, 'Text', '切片 [min, max]：-- / --');
    sliceLabel.Layout.Row = 1;
    sliceLabel.Layout.Column = [6, 10];

    if showMode
        label = uilabel(controls, 'Text', '绘图模式');
        label.Layout.Row = 2;
        label.Layout.Column = 1;
        control = uidropdown(controls, 'Items', {'Slice（二维切片）'}, ...
            'Value', 'Slice（二维切片）', 'Enable', 'off');
        control.Layout.Row = 2;
        control.Layout.Column = [2, 4];
    end
    if showDimension
        label = uilabel(controls, 'Text', '切片维度');
        label.Layout.Row = 3;
        label.Layout.Column = 1;
        control = uidropdown(controls, ...
            'Items', {'Dim 1', 'Dim 2', 'Dim 3'}, ...
            'Value', 'Dim 3', 'Enable', 'off');
        control.Layout.Row = 3;
        control.Layout.Column = 2;
    end
    if showIndex
        label = uilabel(controls, 'Text', '索引');
        label.Layout.Row = 3;
        label.Layout.Column = 3;
        slider = uislider(controls, 'Limits', [1, 2], 'Value', 1, ...
            'MajorTicks', [1, 2], 'Enable', 'off');
        slider.Layout.Row = 3;
        slider.Layout.Column = [4, 6];
        edit = uieditfield(controls, 'numeric', 'Value', 1, 'Enable', 'off');
        edit.Layout.Row = 3;
        edit.Layout.Column = 7;
        play = uibutton(controls, 'Text', '播放', 'Enable', 'off');
        play.Layout.Row = 4;
        play.Layout.Column = 2;
        interval = uieditfield(controls, 'numeric', 'Value', 0.12, 'Enable', 'off');
        interval.Layout.Row = 4;
        interval.Layout.Column = 4;
    end
    if showColor
        label = uilabel(controls, 'Text', '颜色栏');
        label.Layout.Row = 3;
        label.Layout.Column = 9;
        control = uidropdown(controls, 'Items', {'全局范围'}, ...
            'Value', '全局范围', 'Enable', 'off');
        control.Layout.Row = 3;
        control.Layout.Column = 10;
    end
end


function createDisabledVolumeControls(controlPanel, opts)
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

    pending = uilabel(controls, 'Text', '变量：尚未选择', 'FontWeight', 'bold');
    pending.Layout.Row = 1;
    pending.Layout.Column = [1, 5];
    globalLabel = uilabel(controls, 'Text', '全局 [min, max]：-- / --');
    globalLabel.Layout.Row = 1;
    globalLabel.Layout.Column = [6, 9];
    sampleLabel = uilabel(controls, 'Text', '绘制采样：--');
    sampleLabel.Layout.Row = 1;
    sampleLabel.Layout.Column = [10, 14];

    if showMode
        label = uilabel(controls, 'Text', '绘图模式');
        label.Layout.Row = 2;
        label.Layout.Column = 1;
        control = uidropdown(controls, 'Items', {'Volume（三维等值面）'}, ...
            'Value', 'Volume（三维等值面）', 'Enable', 'off');
        control.Layout.Row = 2;
        control.Layout.Column = [2, 4];
    end
    if showIsoMode
        label = uilabel(controls, 'Text', '等值面方式');
        label.Layout.Row = 3;
        label.Layout.Column = 1;
        control = uidropdown(controls, 'Items', {'自动多层'}, ...
            'Value', '自动多层', 'Enable', 'off');
        control.Layout.Row = 3;
        control.Layout.Column = [2, 4];
    end
    if showCount
        label = uilabel(controls, 'Text', '等值面数');
        label.Layout.Row = 4;
        label.Layout.Column = 1;
        control = uispinner(controls, 'Value', opts.NumIsosurfaces, 'Enable', 'off');
        control.Layout.Row = 4;
        control.Layout.Column = 2;
    end
    if showRange
        label = uilabel(controls, 'Text', '范围下限%');
        label.Layout.Row = 4;
        label.Layout.Column = 3;
        lower = uieditfield(controls, 'numeric', ...
            'Value', 100 * opts.IsoRange(1), 'Enable', 'off');
        lower.Layout.Row = 4;
        lower.Layout.Column = 4;
        label = uilabel(controls, 'Text', '范围上限%');
        label.Layout.Row = 4;
        label.Layout.Column = 5;
        upper = uieditfield(controls, 'numeric', ...
            'Value', 100 * opts.IsoRange(2), 'Enable', 'off');
        upper.Layout.Row = 4;
        upper.Layout.Column = 6;
    end
    if showAlpha
        label = uilabel(controls, 'Text', '透明度');
        label.Layout.Row = 4;
        label.Layout.Column = 7;
        slider = uislider(controls, 'Limits', [0.03, 1], ...
            'Value', opts.SurfaceAlpha, 'Enable', 'off');
        slider.Layout.Row = 4;
        slider.Layout.Column = [8, 14];
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
            loadTargetArray(opts.MatFile, selectedVariable);
        opts.MatFile = resolvedFile;
        opts.FieldDimension = fieldDimension;
        opts.PlotType = resolvePlotTypeForField(opts, fieldDimension);
        if fieldDimension == 3
            opts.Dimension = normalizeDimension(opts.Dimension);
        end
        globalRange = validateLoadedArray(fieldData, opts);

        if strcmp(opts.PlotType, 'slice') && fieldDimension == 3
            if opts.Specified.Index
                validateInitialIndex(opts.Index, opts.Dimension, size(fieldData));
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
                createSliceFigure(fieldData, opts, globalRange, fig);
            case 'volume'
                createVolumeFigure(fieldData, opts, globalRange, fig);
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
    showSourceControl = ~opts.Specified.MatFile || ~opts.Specified.Variable;
    showModeControl = fieldDimension == 3 && ~opts.Specified.PlotType;
    showDimensionControl = fieldDimension == 3 && ~opts.Specified.Dimension;
    showIndexControl = fieldDimension == 3 && ~opts.Specified.Index;
    showColorControl = ~opts.Specified.ColorLimits;
    showSliceControlRow = showDimensionControl || showIndexControl || showColorControl;
    showPlaybackControl = showIndexControl;

    figName = sprintf('%s | slice', opts.Variable);
    fig = prepareViewerFigure(existingFig, figName, [120, 80, 1120, 800], opts.Visible);
    controlPanelHeight = 100 + 34 * double(showModeControl) + ...
        42 * double(showSliceControlRow) + 36 * double(showPlaybackControl);
    if showSourceControl
        mainGrid = uigridlayout(fig, [3, 1]);
        mainGrid.RowHeight = {sourceSelectorHeight(opts), '1x', controlPanelHeight};
        plotRow = 2;
        controlRow = 3;
        [filePathEdit, browseButton, variableDropDown] = ...
            addSourceSelector(mainGrid, opts, opts.Variable);
    else
        mainGrid = uigridlayout(fig, [2, 1]);
        mainGrid.RowHeight = {'1x', controlPanelHeight};
        plotRow = 1;
        controlRow = 2;
        filePathEdit = gobjects(0);
        browseButton = gobjects(0);
        variableDropDown = gobjects(0);
    end
    mainGrid.Padding = [12, 12, 12, 12];
    mainGrid.RowSpacing = 8;

    plotGrid = uigridlayout(mainGrid, [1, 1]);
    plotGrid.Layout.Row = plotRow;
    plotGrid.Padding = [0, 0, 0, 18];
    plotGrid.RowSpacing = 0;
    plotGrid.ColumnSpacing = 0;
    ax = uiaxes(plotGrid);
    ax.Box = 'on';
    ax.FontName = 'Consolas';
    ax.FontSize = 12;
    ax.Toolbar.Visible = 'on';
    colormap(ax, opts.Colormap);
    cb = colorbar(ax);
    cb.Label.String = 'Value';

    controlPanel = uipanel(mainGrid, 'Title', '切片控制', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.98, 0.98, 0.99]);
    controlPanel.Layout.Row = controlRow;
    controls = uigridlayout(controlPanel, [4, 10]);
    controls.RowHeight = {28, 34 * double(showModeControl), ...
        42 * double(showSliceControlRow), 36 * double(showPlaybackControl)};
    controls.ColumnWidth = {62, 130, 42, '1x', '1x', '1x', 72, 24, 60, 145};
    controls.Padding = [10, 14, 10, 8];
    controls.ColumnSpacing = 7;
    controls.RowSpacing = 6;

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
            'Items', {'Dim 1', 'Dim 2', 'Dim 3'}, ...
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

    playButton = gobjects(0);
    playbackIntervalEdit = gobjects(0);
    playbackTimer = [];
    if showPlaybackControl
        playbackText = uilabel(controls, 'Text', '自动播放');
        playbackText.Layout.Row = 4;
        playbackText.Layout.Column = 1;
        playButton = uibutton(controls, 'push', 'Text', '播放');
        playButton.Layout.Row = 4;
        playButton.Layout.Column = 2;
        intervalText = uilabel(controls, 'Text', '间隔(s)');
        intervalText.Layout.Row = 4;
        intervalText.Layout.Column = 3;
        playbackIntervalEdit = uieditfield(controls, 'numeric', ...
            'Limits', [0.03, 10], 'ValueDisplayFormat', '%.2f', 'Value', 0.12);
        playbackIntervalEdit.Layout.Row = 4;
        playbackIntervalEdit.Layout.Column = 4;
        playbackHint = uilabel(controls, ...
            'Text', '从当前索引向后播放，到末尾后从 1 循环。', ...
            'FontColor', [0.35, 0.35, 0.38]);
        playbackHint.Layout.Row = 4;
        playbackHint.Layout.Column = [5, 10];
        playbackTimer = timer('ExecutionMode', 'fixedSpacing', ...
            'BusyMode', 'drop', 'Period', playbackIntervalEdit.Value, ...
            'TimerFcn', @(source, event) advanceSlicePlayback(fig, source, event));
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
        colorText = uilabel(controls, 'Text', '颜色栏');
        colorText.Layout.Row = 3;
        colorText.Layout.Column = 9;
        colorDropDown = uidropdown(controls);
        colorDropDown.Layout.Row = 3;
        colorDropDown.Layout.Column = 10;
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
        'FieldDimension', fieldDimension, ...
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
        'FilePathEdit', filePathEdit, ...
        'BrowseButton', browseButton, ...
        'VariableDropDown', variableDropDown, ...
        'ModeDropDown', modeDropDown, ...
        'DimensionDropDown', dimDropDown, ...
        'IndexSlider', indexSlider, ...
        'IndexEdit', indexEdit, ...
        'ColorDropDown', colorDropDown, ...
        'SliceLabel', sliceLabel, ...
        'PlayButton', playButton, ...
        'PlaybackIntervalEdit', playbackIntervalEdit, ...
        'PlaybackTimer', playbackTimer, ...
        'LastSliceRenderClock', tic);
    fig.UserData = state;

    if ~isempty(modeDropDown) && isgraphics(modeDropDown)
        modeDropDown.ValueChangedFcn = @(source, event) onPlotModeChanged(fig, source, event);
    end
    if ~isempty(variableDropDown) && isgraphics(variableDropDown)
        variableDropDown.ValueChangedFcn = ...
            @(source, event) onVariableChanged(fig, source, event);
    end
    if ~isempty(filePathEdit) && isgraphics(filePathEdit)
        filePathEdit.ValueChangedFcn = ...
            @(source, event) onMatFilePathChanged(fig, source, event);
        browseButton.ButtonPushedFcn = ...
            @(source, event) browseForMatFile(fig, source, event);
    end
    if ~isempty(dimDropDown) && isgraphics(dimDropDown)
        dimDropDown.ValueChangedFcn = @(source, event) onSliceDimensionChanged(fig, source, event);
    end
    if ~isempty(indexSlider) && isgraphics(indexSlider)
        indexSlider.ValueChangingFcn = @(source, event) onSliceSliderMoving(fig, source, event);
        indexSlider.ValueChangedFcn = @(source, event) onSliceSliderChanged(fig, source, event);
        indexEdit.ValueChangedFcn = @(source, event) onSliceIndexEdited(fig, source, event);
    end
    if ~isempty(playButton) && isgraphics(playButton)
        playButton.ButtonPushedFcn = @(source, event) toggleViewerPlayback(fig, source, event);
        playbackIntervalEdit.ValueChangedFcn = ...
            @(source, event) updateViewerPlaybackPeriod(fig, source, event);
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
    pauseViewerPlayback(fig);
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
        pauseViewerPlayback(fig);
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
        renderSlice(fig, index, false);
    end
end


function onSliceSliderChanged(fig, source, ~)
    if isvalid(fig)
        pauseViewerPlayback(fig);
        renderSlice(fig, round(source.Value), true);
    end
end


function onSliceIndexEdited(fig, source, ~)
    if isvalid(fig)
        pauseViewerPlayback(fig);
        renderSlice(fig, round(source.Value), true);
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
    % and the second is vertical, rather than silently treating matrix rows
    % as a physical X coordinate.
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
                state.Axes.CLim = makeSafeLimits(sliceRange);
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
        formatNumber(sliceRange(1)), formatNumber(sliceRange(2)));

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
    fig.UserData = state;
    drawnow limitrate nocallbacks
end


function fig = createVolumeFigure(volumeData, opts, globalRange, existingFig)
    if nargin < 4
        existingFig = [];
    end
    if opts.FieldDimension ~= 3
        error('visualizeMatField:VolumeRequires3D', ...
            'Volume mode requires a real numeric 3-D array.');
    end
    showSourceControl = ~opts.Specified.MatFile || ~opts.Specified.Variable;
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
    exactValueLimits = makeSafeLimits(globalRange);
    exactIsoValue = max(exactValueLimits(1), min(exactValueLimits(2), exactIsoValue));
    showExactPlaybackInitially = showExactValueControl && strcmp(isoSelectionMode, 'single');
    baseControlPanelHeight = 100 + 34 * double(showModeControl) + ...
        36 * double(showIsoModeControl) + 46 * double(showVolumeControlRow);

    figName = sprintf('%s | 3-D isosurfaces', opts.Variable);
    fig = prepareViewerFigure(existingFig, figName, [120, 70, 1180, 830], opts.Visible);
    controlPanelHeight = baseControlPanelHeight + ...
        36 * double(showExactPlaybackInitially);
    if showSourceControl
        mainGrid = uigridlayout(fig, [3, 1]);
        mainGrid.RowHeight = {sourceSelectorHeight(opts), '1x', controlPanelHeight};
        plotRow = 2;
        controlRow = 3;
        [filePathEdit, browseButton, variableDropDown] = ...
            addSourceSelector(mainGrid, opts, opts.Variable);
    else
        mainGrid = uigridlayout(fig, [2, 1]);
        mainGrid.RowHeight = {'1x', controlPanelHeight};
        plotRow = 1;
        controlRow = 2;
        filePathEdit = gobjects(0);
        browseButton = gobjects(0);
        variableDropDown = gobjects(0);
    end
    mainGrid.Padding = [18, 18, 18, 18];
    mainGrid.RowSpacing = 8;

    plotGrid = uigridlayout(mainGrid, [1, 1]);
    plotGrid.Layout.Row = plotRow;
    plotGrid.Padding = [0, 0, 0, 18];
    plotGrid.RowSpacing = 0;
    plotGrid.ColumnSpacing = 0;
    ax = uiaxes(plotGrid);
    ax.Box = 'on';
    ax.FontName = 'Consolas';
    ax.FontSize = 12;
    ax.Toolbar.Visible = 'on';
    colormap(ax, opts.Colormap);
    cb = colorbar(ax);
    cb.Label.String = 'Value';

    controlPanel = uipanel(mainGrid, 'Title', '三维等值面控制', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.98, 0.98, 0.99]);
    controlPanel.Layout.Row = controlRow;
    controls = uigridlayout(controlPanel, [5, 14]);
    controls.RowHeight = {28, 34 * double(showModeControl), ...
        36 * double(showIsoModeControl), 46 * double(showVolumeControlRow), ...
        36 * double(showExactPlaybackInitially)};
    controls.ColumnWidth = {82, 62, 76, 62, 76, 62, 55, ...
        '1x', '1x', '1x', 55, 62, 62, 72};
    controls.Padding = [10, 14, 10, 8];
    controls.ColumnSpacing = 7;
    controls.RowSpacing = 6;

    variableLabel = uilabel(controls, ...
        'Text', sprintf('变量：%s', opts.Variable), 'FontWeight', 'bold');
    variableLabel.Layout.Row = 1;
    variableLabel.Layout.Column = [1, 5];
    variableLabel.Tooltip = opts.MatFile;

    globalLabel = uilabel(controls, ...
        'Text', sprintf('全局 [min, max]：%s / %s', ...
        formatNumber(globalRange(1)), formatNumber(globalRange(2))));
    globalLabel.Layout.Row = 1;
    globalLabel.Layout.Column = [6, 9];

    sampleIndices = cell(1, 3);
    for dim = 1:3
        sampleIndices{dim} = makeSampleIndices(size(volumeData, dim), opts.MaxRenderSize);
    end
    sampledSize = cellfun(@numel, sampleIndices);
    samplingLabel = uilabel(controls, ...
        'Text', sprintf('绘制采样：%s（统计使用完整数据）', mat2str(sampledSize)));
    samplingLabel.Layout.Row = 1;
    samplingLabel.Layout.Column = [10, 14];

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
        modeHint.Layout.Column = [5, 14];
    end

    isoModeDropDown = gobjects(0);
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

    lowerEdit = gobjects(0);
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
        configureValueSliderTicks(exactValueSlider, globalRange);
        exactControls = {exactValueText, exactValueEdit, exactValueSlider};
    end

    playButton = gobjects(0);
    playbackIntervalEdit = gobjects(0);
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
            'TimerFcn', @(source, event) advanceExactIsoPlayback(fig, source, event));
    end

    setControlGroupVisible(automaticControls, strcmp(isoSelectionMode, 'automatic'));
    setControlGroupVisible(exactControls, strcmp(isoSelectionMode, 'single'));
    setControlGroupVisible(playbackControls, showExactPlaybackInitially);
    setVolumeAlphaLayout(alphaText, alphaSlider, isoSelectionMode);

    if isnumeric(opts.ColorLimits)
        volumeClim = makeSafeLimits(opts.ColorLimits);
    else
        volumeClim = makeSafeLimits(globalRange);
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
        'Patches', gobjects(0));
    fig.UserData = state;

    if ~isempty(modeDropDown) && isgraphics(modeDropDown)
        modeDropDown.ValueChangedFcn = @(source, event) onPlotModeChanged(fig, source, event);
    end
    if ~isempty(variableDropDown) && isgraphics(variableDropDown)
        variableDropDown.ValueChangedFcn = ...
            @(source, event) onVariableChanged(fig, source, event);
    end
    if ~isempty(filePathEdit) && isgraphics(filePathEdit)
        filePathEdit.ValueChangedFcn = ...
            @(source, event) onMatFilePathChanged(fig, source, event);
        browseButton.ButtonPushedFcn = ...
            @(source, event) browseForMatFile(fig, source, event);
    end
    if ~isempty(isoModeDropDown) && isgraphics(isoModeDropDown)
        isoModeDropDown.ValueChangedFcn = ...
            @(source, event) onIsoSelectionModeChanged(fig, source, event);
    end
    if ~isempty(countSpinner) && isgraphics(countSpinner)
        countSpinner.ValueChangedFcn = ...
            @(source, event) onAutomaticIsoParametersChanged(fig, source, event);
    end
    if ~isempty(lowerEdit) && isgraphics(lowerEdit)
        lowerEdit.ValueChangedFcn = ...
            @(source, event) onAutomaticIsoParametersChanged(fig, source, event);
        upperEdit.ValueChangedFcn = ...
            @(source, event) onAutomaticIsoParametersChanged(fig, source, event);
    end
    if ~isempty(exactValueSlider) && isgraphics(exactValueSlider)
        exactValueSlider.ValueChangingFcn = ...
            @(source, event) previewExactIsoValue(fig, event.Value);
        exactValueSlider.ValueChangedFcn = ...
            @(source, event) commitExactIsoValue(fig, source.Value);
        exactValueEdit.ValueChangedFcn = ...
            @(source, event) commitExactIsoValue(fig, source.Value);
    end
    if ~isempty(alphaSlider) && isgraphics(alphaSlider)
        alphaSlider.ValueChangingFcn = ...
            @(source, event) changeSurfaceAlpha(fig, event.Value, false);
        alphaSlider.ValueChangedFcn = ...
            @(source, event) changeSurfaceAlpha(fig, source.Value, true);
    end
    if ~isempty(playButton) && isgraphics(playButton)
        playButton.ButtonPushedFcn = @(source, event) toggleViewerPlayback(fig, source, event);
        playbackIntervalEdit.ValueChangedFcn = ...
            @(source, event) updateViewerPlaybackPeriod(fig, source, event);
    end

    renderVolume(fig);
end


function onAutomaticIsoParametersChanged(fig, ~, ~)
    if isvalid(fig)
        renderVolume(fig);
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
    pauseViewerPlayback(fig);
    state = fig.UserData;
    state.IsoSelectionMode = char(source.Value);
    setControlGroupVisible(state.AutomaticControls, ...
        strcmp(state.IsoSelectionMode, 'automatic'));
    setControlGroupVisible(state.ExactControls, ...
        strcmp(state.IsoSelectionMode, 'single'));
    showPlayback = strcmp(state.IsoSelectionMode, 'single');
    setControlGroupVisible(state.PlaybackControls, showPlayback);
    rowHeights = state.ControlsGrid.RowHeight;
    rowHeights{5} = 36 * double(showPlayback);
    state.ControlsGrid.RowHeight = rowHeights;
    mainRowHeights = state.MainGrid.RowHeight;
    mainRowHeights{state.ControlPanelRow} = ...
        state.BaseControlPanelHeight + 36 * double(showPlayback);
    state.MainGrid.RowHeight = mainRowHeights;
    setVolumeAlphaLayout(state.AlphaText, state.AlphaSlider, ...
        state.IsoSelectionMode);
    fig.UserData = state;
    renderVolume(fig);
end


function previewExactIsoValue(fig, value)
    if ~isvalid(fig)
        return
    end
    pauseViewerPlayback(fig);
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
    pauseViewerPlayback(fig);
    state = fig.UserData;
    state.ExactIsoValue = double(value);
    if ~isempty(state.ExactValueEdit) && isgraphics(state.ExactValueEdit)
        state.ExactValueEdit.Value = state.ExactIsoValue;
        state.ExactValueSlider.Value = state.ExactIsoValue;
    end
    fig.UserData = state;
    renderVolume(fig);
end


function toggleViewerPlayback(fig, source, ~)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
    playbackTimer = state.PlaybackTimer;
    if isempty(playbackTimer) || ~isvalid(playbackTimer)
        return
    end
    if strcmp(playbackTimer.Running, 'on')
        stop(playbackTimer);
        source.Text = '播放';
    else
        playbackTimer.Period = state.PlaybackIntervalEdit.Value;
        source.Text = '暂停';
        start(playbackTimer);
    end
end


function updateViewerPlaybackPeriod(fig, source, ~)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
    playbackTimer = state.PlaybackTimer;
    if isempty(playbackTimer) || ~isvalid(playbackTimer)
        return
    end
    wasRunning = strcmp(playbackTimer.Running, 'on');
    if wasRunning
        stop(playbackTimer);
    end
    playbackTimer.Period = source.Value;
    if wasRunning
        start(playbackTimer);
    end
end


function advanceSlicePlayback(fig, ~, ~)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
    nextIndex = state.Index + 1;
    if nextIndex > state.DataSize(state.Dimension)
        nextIndex = 1;
    end
    renderSlice(fig, nextIndex, true);
end


function advanceExactIsoPlayback(fig, ~, ~)
    if ~isvalid(fig)
        return
    end
    state = fig.UserData;
    valueSpan = diff(state.GlobalRange);
    if valueSpan <= 0
        pauseViewerPlayback(fig);
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
    renderVolume(fig);
end


function pauseViewerPlayback(fig)
    if isempty(fig) || ~isvalid(fig) || isempty(fig.UserData) || ...
            ~isfield(fig.UserData, 'PlaybackTimer')
        return
    end
    state = fig.UserData;
    playbackTimer = state.PlaybackTimer;
    if ~isempty(playbackTimer) && isvalid(playbackTimer) && ...
            strcmp(playbackTimer.Running, 'on')
        stop(playbackTimer);
    end
    if isfield(state, 'PlayButton') && ~isempty(state.PlayButton) && ...
            isgraphics(state.PlayButton)
        if ~strcmp(state.PlayButton.Text, '播放')
            state.PlayButton.Text = '播放';
        end
    end
end


function stopViewerPlayback(fig, deleteTimer)
    if isempty(fig) || ~isvalid(fig) || isempty(fig.UserData) || ...
            ~isfield(fig.UserData, 'PlaybackTimer')
        return
    end
    pauseViewerPlayback(fig);
    playbackTimer = fig.UserData.PlaybackTimer;
    if deleteTimer && ~isempty(playbackTimer) && isvalid(playbackTimer)
        delete(playbackTimer);
    end
end


function closeViewerFigure(fig, ~)
    if ~isvalid(fig)
        return
    end
    stopViewerPlayback(fig, true);
    delete(fig);
end


function setControlGroupVisible(controls, isVisible)
    visibility = 'off';
    if isVisible
        visibility = 'on';
    end
    for index = 1:numel(controls)
        if isgraphics(controls{index})
            controls{index}.Visible = visibility;
        end
    end
end


function setVolumeAlphaLayout(alphaText, alphaSlider, isoSelectionMode)
    if isempty(alphaSlider) || ~isgraphics(alphaSlider)
        return
    end
    if strcmp(isoSelectionMode, 'single')
        alphaText.Layout.Column = 11;
        alphaSlider.Layout.Column = [12, 14];
    else
        alphaText.Layout.Column = 7;
        alphaSlider.Layout.Column = [8, 14];
    end
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
        navigationState = captureAxesNavigation(state.Axes);
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
            sprintf('常量场：%s', formatNumber(state.GlobalRange(1))), ...
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
    state.Axes.XLim = makeSafeLimits([dim1Indices(1), dim1Indices(end)]);
    state.Axes.YLim = makeSafeLimits([dim2Indices(1), dim2Indices(end)]);
    state.Axes.ZLim = makeSafeLimits([dim3Indices(1), dim3Indices(end)]);
    axis(state.Axes, 'vis3d');
    daspect(state.Axes, [1, 1, 1]);
    if state.HasRendered
        restoreAxesNavigation(state.Axes, navigationState);
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
            state.Variable, formatNumber(levels));
    else
        titleText = sprintf('%s  |  %d isosurfaces: %s ... %s', ...
            state.Variable, numel(patches), formatNumber(levels(1)), ...
            formatNumber(levels(end)));
    end
    title(state.Axes, titleText, 'Interpreter', 'none');

    state.NumIsosurfaces = count;
    state.IsoRange = isoRange;
    state.ExactIsoValue = exactIsoValue;
    state.SurfaceAlpha = surfaceAlpha;
    state.Patches = patches;
    state.HasRendered = true;
    state = ensureVolumeInteractivity(state);
    fig.UserData = state;
    drawnow
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


function configureSliderTicks(slider, axisLength)
    slider.MajorTicks = unique(round(linspace(1, axisLength, min(5, axisLength))));
    slider.MinorTicks = [];
end


function configureValueSliderTicks(slider, valueRange)
    ticks = unique(linspace(valueRange(1), valueRange(2), 5));
    slider.MajorTicks = ticks;
    slider.MajorTickLabels = arrayfun(@formatNumber, ticks, 'UniformOutput', false);
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
    dimension = double(dimension);
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
         value == fix(value) && value >= 1 && value <= 3);
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
