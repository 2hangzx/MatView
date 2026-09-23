classdef Input
    %INPUT Parse and validate the public visualizeMatField call contract.
    methods (Static)
        function opts = parse(inputs, sourceInputName)
            if nargin < 2
                sourceInputName = '';
            end
            [sourceInput, sourceSpecified, variablePath, variableSpecified, ...
                optionalInputs] = matfield.Input.splitViewerInputs(inputs);
            opts = matfield.Input.parseViewerInputs(sourceInput, sourceSpecified, ...
                sourceInputName, variablePath, variableSpecified, optionalInputs{:});
        end

        function [sourceInput, sourceSpecified, variablePath, variableSpecified, ...
                optionalInputs] = splitViewerInputs(inputs)
            optionNames = ["SourceType", "WorkspaceVariable", "PlotType", ...
                "Dimension", "Index", "Colormap", "ColorLimits", ...
                "NumIsosurfaces", "IsoRange", "IsoValues", ...
                "SurfaceAlpha", "MaxRenderSize", "Visible"];
            sourceInput = [];
            sourceSpecified = false;
            variablePath = '';
            variableSpecified = false;
            optionalInputs = inputs;
            if isempty(inputs)
                return
            end

            firstInput = inputs{1};
            if isempty(firstInput)
                optionalInputs = inputs(2:end);
            elseif matfield.Input.isTextScalar(firstInput) && ...
                    any(strcmpi(string(firstInput), optionNames))
                % The Name-Value list starts without a positional source.
            else
                sourceInput = firstInput;
                sourceSpecified = true;
                optionalInputs = inputs(2:end);
            end

            if ~sourceSpecified || isempty(optionalInputs)
                return
            end
            firstInput = optionalInputs{1};
            if isempty(firstInput)
                optionalInputs = optionalInputs(2:end);
            elseif matfield.Input.isTextScalar(firstInput) && ...
                    any(strcmpi(string(firstInput), optionNames))
                % Name-Value inputs start immediately after the source.
            else
                variablePath = firstInput;
                variableSpecified = true;
                optionalInputs = optionalInputs(2:end);
            end
        end

        function opts = parseViewerInputs(sourceInput, sourceSpecified, ...
                sourceInputName, variablePath, variableSpecified, varargin)
            plotTypeNames = ["slice", "figure", "volume", "3d", "isosurface"];

            if sourceSpecified && ~(matfield.Input.isTextScalar(sourceInput) || ...
                    isnumeric(sourceInput) || isstruct(sourceInput))
                error('visualizeMatField:InvalidSource', ...
                    ['The first positional input must be a MAT-file path, a ', ...
                     'numeric array, or a scalar structure.']);
            end
            if sourceSpecified && isstruct(sourceInput) && ~isscalar(sourceInput)
                error('visualizeMatField:InvalidMemoryStructure', ...
                    'A directly supplied structure must be scalar.');
            end
            if variableSpecified && ~matfield.Input.isTextScalar(variablePath)
                error('visualizeMatField:InvalidVariable', ...
                    'The second positional input variablePath must be text.');
            end
            if sourceSpecified && matfield.Input.isTextScalar(sourceInput) && ...
                    strcmpi(strtrim(char(sourceInput)), 'MatFile')
                error('visualizeMatField:RequiredInputsMustBePositional', ...
                    ['MAT-file paths remain positional inputs. Use ', ...
                     'visualizeMatField(matFile, [variablePath], Name, Value, ...).']);
            end
            if ~isempty(varargin) && matfield.Input.isTextScalar(varargin{1}) && ...
                    any(lower(string(varargin{1})) == plotTypeNames)
                error('visualizeMatField:PlotTypeMustBeNameValue', ...
                    ['PlotType must use Name-Value syntax, for example ', ...
                     '''PlotType'', ''slice''.']);
            end
            if mod(numel(varargin), 2) ~= 0
                error('visualizeMatField:IncompleteNameValuePair', ...
                    'Optional inputs must be complete Name-Value pairs.');
            end

            parser = inputParser;
            parser.FunctionName = 'visualizeMatField';
            parser.CaseSensitive = false;
            parser.PartialMatching = false;
            addParameter(parser, 'SourceType', 'matfile', @matfield.Input.isTextScalar);
            addParameter(parser, 'WorkspaceVariable', '', @matfield.Input.isTextScalar);
            addParameter(parser, 'PlotType', 'volume', @matfield.Input.isTextScalar);
            addParameter(parser, 'Dimension', [], @matfield.Input.isDimensionValue);
            addParameter(parser, 'Index', [], @matfield.Input.isIndexValue);
            addParameter(parser, 'Colormap', 'turbo', @matfield.Input.isTextScalar);
            addParameter(parser, 'ColorLimits', 'global', @matfield.Input.isColorLimitsValue);
            addParameter(parser, 'NumIsosurfaces', 5, ...
                @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
                x == fix(x) && x >= 1 && x <= 12);
            addParameter(parser, 'IsoRange', [0.15, 0.85], ...
                @(x) isnumeric(x) && numel(x) == 2 && all(isfinite(x)) && ...
                x(1) >= 0 && x(2) <= 1 && x(1) < x(2));
            addParameter(parser, 'IsoValues', [], @matfield.Input.isIsoValuesValue);
            addParameter(parser, 'SurfaceAlpha', 0.22, ...
                @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 1);
            addParameter(parser, 'MaxRenderSize', 96, ...
                @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
                x == fix(x) && x >= 16);
            addParameter(parser, 'Visible', 'on', ...
                @(x) matfield.Input.isTextScalar(x) && ...
                any(strcmpi(string(x), ["on", "off"])));
            parse(parser, varargin{:});

            usingDefaults = parser.UsingDefaults;
            opts = parser.Results;
            explicitSourceType = ~ismember('SourceType', usingDefaults);
            workspaceVariableSpecified = ...
                ~ismember('WorkspaceVariable', usingDefaults);
            requestedSourceType = matfield.Input.normalizeSourceType(opts.SourceType);

            if sourceSpecified
                if matfield.Input.isTextScalar(sourceInput)
                    inferredSourceType = 'matfile';
                else
                    inferredSourceType = 'memory';
                end
                if explicitSourceType && ~strcmp(requestedSourceType, inferredSourceType)
                    error('visualizeMatField:ConflictingSourceType', ...
                        ['SourceType "%s" conflicts with the first positional ', ...
                         'input, which identifies a %s source.'], ...
                        requestedSourceType, inferredSourceType);
                end
                sourceType = inferredSourceType;
            else
                sourceType = requestedSourceType;
            end

            if strcmp(sourceType, 'memory') && ~sourceSpecified
                error('visualizeMatField:MemorySourceRequiresValue', ...
                    'SourceType ''memory'' requires a direct numeric or struct input.');
            end
            if workspaceVariableSpecified && ~strcmp(sourceType, 'workspace')
                error('visualizeMatField:WorkspaceVariableRequiresWorkspace', ...
                    'WorkspaceVariable requires SourceType ''workspace''.');
            end

            matFile = '';
            memoryRootName = '';
            memoryValue = [];
            targetSpecified = variableSpecified;
            targetPath = char(string(variablePath));
            switch sourceType
                case 'matfile'
                    if sourceSpecified
                        matFile = char(sourceInput);
                    end
                case 'workspace'
                    if sourceSpecified
                        error('visualizeMatField:WorkspaceSourceIsNameValue', ...
                            ['Workspace browsing is selected with ', ...
                             '''SourceType'', ''workspace'', not a positional input.']);
                    end
                    targetPath = char(opts.WorkspaceVariable);
                    targetSpecified = workspaceVariableSpecified;
                case 'memory'
                    memoryValue = sourceInput;
                    memoryRootName = char(string(sourceInputName));
                    if isempty(memoryRootName) || ~isvarname(memoryRootName)
                        memoryRootName = 'memoryData';
                    end
                    if isnumeric(memoryValue)
                        if variableSpecified
                            error('visualizeMatField:MemoryArrayHasNoTargetPath', ...
                                'A direct numeric array does not accept a second positional target path.');
                        end
                        targetPath = memoryRootName;
                        targetSpecified = true;
                    end
            end

            if targetSpecified && isempty(strtrim(targetPath))
                error('visualizeMatField:VariableRequired', ...
                    'An explicitly supplied target variable path cannot be empty.');
            end

            opts.Specified = struct( ...
                'SourceType', explicitSourceType || sourceSpecified, ...
                'MatFile', sourceSpecified && strcmp(sourceType, 'matfile'), ...
                'Variable', targetSpecified, ...
                'WorkspaceVariable', workspaceVariableSpecified, ...
                'PlotType', ~ismember('PlotType', usingDefaults), ...
                'Dimension', ~ismember('Dimension', usingDefaults), ...
                'Index', ~ismember('Index', usingDefaults), ...
                'ColorLimits', ~ismember('ColorLimits', usingDefaults), ...
                'NumIsosurfaces', ~ismember('NumIsosurfaces', usingDefaults), ...
                'IsoRange', ~ismember('IsoRange', usingDefaults), ...
                'IsoValues', ~ismember('IsoValues', usingDefaults), ...
                'SurfaceAlpha', ~ismember('SurfaceAlpha', usingDefaults), ...
                'MaxRenderSize', ~ismember('MaxRenderSize', usingDefaults));
            opts.SourceType = sourceType;
            opts.RequestedSourceType = sourceType;
            opts.MatFile = matFile;
            opts.Variable = targetPath;
            opts.WorkspaceVariable = char(opts.WorkspaceVariable);
            opts.Source = matfield.Data.makeSource( ...
                sourceType, matFile, memoryValue, memoryRootName);
            opts.PlotType = matfield.Input.normalizePlotType(opts.PlotType);
            opts.RequestedPlotType = opts.PlotType;
            opts.Colormap = char(opts.Colormap);
            opts.IsoRange = double(opts.IsoRange(:).');
            opts.IsoValues = unique(double(opts.IsoValues(:).'));
            opts.Visible = char(lower(string(opts.Visible)));

            matfield.Input.validateOptionHierarchy(opts);
            if matfield.Input.isTextScalar(opts.ColorLimits)
                opts.ColorLimits = char(lower(string(opts.ColorLimits)));
                if ~any(strcmp(opts.ColorLimits, {'global', 'slice'}))
                    error('visualizeMatField:ColorLimits', ...
                        ['ColorLimits must be ''global'', ''slice'', or a ', ...
                         'numeric [low high] pair.']);
                end
            else
                opts.ColorLimits = double(opts.ColorLimits(:).');
            end
            opts.SourceChangeDefaults = struct( ...
                'PlotType', opts.PlotType, ...
                'Dimension', opts.Dimension, ...
                'Index', opts.Index, ...
                'ColorLimits', opts.ColorLimits, ...
                'NumIsosurfaces', opts.NumIsosurfaces, ...
                'IsoRange', opts.IsoRange, ...
                'IsoValues', opts.IsoValues, ...
                'SurfaceAlpha', opts.SurfaceAlpha);
        end

        function validateOptionHierarchy(opts)
            if opts.Specified.Index && ~opts.Specified.Dimension
                error('visualizeMatField:IndexRequiresDimension', ...
                    'Index can only be specified with an explicit Dimension.');
            end
            if (opts.Specified.Dimension || opts.Specified.Index) && ...
                    (~opts.Specified.PlotType || ~strcmp(opts.PlotType, 'slice'))
                error('visualizeMatField:SliceOptionRequiresSliceMode', ...
                    'Dimension and Index require an explicit slice PlotType.');
            end

            volumeOptionSpecified = opts.Specified.NumIsosurfaces || ...
                opts.Specified.IsoRange || opts.Specified.IsoValues || ...
                opts.Specified.SurfaceAlpha || opts.Specified.MaxRenderSize;
            if volumeOptionSpecified && ...
                    (~opts.Specified.PlotType || ~strcmp(opts.PlotType, 'volume'))
                error('visualizeMatField:VolumeOptionRequiresVolumeMode', ...
                    ['NumIsosurfaces, IsoRange, IsoValues, SurfaceAlpha and ', ...
                     'MaxRenderSize require an explicit volume PlotType.']);
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

        function sourceType = normalizeSourceType(sourceType)
            switch lower(char(string(sourceType)))
                case {'matfile', 'mat'}
                    sourceType = 'matfile';
                case {'workspace', 'base'}
                    sourceType = 'workspace';
                case {'memory'}
                    sourceType = 'memory';
                otherwise
                    error('visualizeMatField:SourceType', ...
                        'SourceType must be ''matfile'', ''workspace'', or ''memory''.');
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
            tf = (ischar(value) && isrow(value)) || ...
                (isstring(value) && isscalar(value));
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
            tf = matfield.Input.isTextScalar(value) || ...
                (isnumeric(value) && numel(value) == 2 && ...
                all(isfinite(value)) && value(1) <= value(2));
        end

        function tf = isIsoValuesValue(value)
            tf = isempty(value) || ...
                (isnumeric(value) && isvector(value) && all(isfinite(value)));
        end
    end
end
