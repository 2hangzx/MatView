classdef Input
    %INPUT Parse and validate the public visualizeMatField call contract.
    methods (Static)
        function opts = parse(inputs)
            %PARSE Convert positional and Name-Value inputs into one options struct.
            [matFile, matFileSpecified, variablePath, variableSpecified, ...
                optionalInputs] = matfield.Input.splitViewerInputs(inputs);
            opts = matfield.Input.parseViewerInputs(matFile, matFileSpecified, ...
                variablePath, variableSpecified, optionalInputs{:});
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
            elseif matfield.Input.isTextScalar(firstInput) && ...
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
            elseif matfield.Input.isTextScalar(firstInput) && ...
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
        
            if matFileSpecified && ~matfield.Input.isTextScalar(matFile)
                error('visualizeMatField:InvalidMatFile', ...
                    'The first positional input matFile must be a character vector or string scalar.');
            end
            if variableSpecified && ~matfield.Input.isTextScalar(variablePath)
                error('visualizeMatField:InvalidVariable', ...
                    'The second positional input variablePath must be a character vector or string scalar.');
            end
            if matFileSpecified && strcmpi(strtrim(char(matFile)), 'MatFile')
                error('visualizeMatField:RequiredInputsMustBePositional', ...
                    ['matFile and variablePath are optional positional inputs, not ', ...
                     'Name-Value parameters. Use visualizeMatField([matFile], ', ...
                     '[variablePath], Name, Value, ...).']);
            end
            if ~isempty(varargin) && matfield.Input.isTextScalar(varargin{1}) && ...
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
            parser.FunctionName = 'visualizeMatField';
            parser.CaseSensitive = false;
            parser.PartialMatching = false;
            addParameter(parser, 'PlotType', 'volume', @matfield.Input.isTextScalar);
            addParameter(parser, 'Dimension', [], @matfield.Input.isDimensionValue);
            addParameter(parser, 'Index', [], @matfield.Input.isIndexValue);
            addParameter(parser, 'Colormap', 'turbo', @matfield.Input.isTextScalar);
            addParameter(parser, 'ColorLimits', 'global', @matfield.Input.isColorLimitsValue);
            addParameter(parser, 'NumIsosurfaces', 5, ...
                @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x == fix(x) && x >= 1 && x <= 12);
            addParameter(parser, 'IsoRange', [0.15, 0.85], ...
                @(x) isnumeric(x) && numel(x) == 2 && all(isfinite(x)) && ...
                     x(1) >= 0 && x(2) <= 1 && x(1) < x(2));
            addParameter(parser, 'IsoValues', [], @matfield.Input.isIsoValuesValue);
            addParameter(parser, 'SurfaceAlpha', 0.22, ...
                @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 1);
            addParameter(parser, 'MaxRenderSize', 96, ...
                @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x == fix(x) && x >= 16);
            addParameter(parser, 'Visible', 'on', ...
                @(x) matfield.Input.isTextScalar(x) && any(strcmpi(string(x), ["on", "off"])));
        
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
            opts.PlotType = matfield.Input.normalizePlotType(opts.PlotType);
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
        
            if matfield.Input.isTextScalar(opts.ColorLimits)
                opts.ColorLimits = char(lower(string(opts.ColorLimits)));
                if ~any(strcmp(opts.ColorLimits, {'global', 'slice'}))
                    error('visualizeMatField:ColorLimits', ...
                        'ColorLimits must be ''global'', ''slice'', or a numeric [low high] pair.');
                end
            else
                opts.ColorLimits = double(opts.ColorLimits(:).');
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
            tf = matfield.Input.isTextScalar(value) || ...
                (isnumeric(value) && numel(value) == 2 && all(isfinite(value)) && value(1) <= value(2));
        end

        function tf = isIsoValuesValue(value)
            tf = isempty(value) || ...
                (isnumeric(value) && isvector(value) && all(isfinite(value)));
        end

    end
end
