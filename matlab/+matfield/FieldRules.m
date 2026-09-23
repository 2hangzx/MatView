classdef FieldRules
    %FIELDRULES Shared classification and validation for drawable arrays.
    methods (Static)
        function info = emptyInfo()
            info = struct('Path', {}, 'Size', {}, 'Dimension', {});
        end

        function info = makeInfo(path, dataSize, dimension)
            info = struct('Path', char(path), ...
                'Size', double(dataSize(:).'), 'Dimension', double(dimension));
        end

        function dimension = classifyArray(value)
            dimension = 0;
            if isnumeric(value) && isreal(value)
                dimension = matfield.FieldRules.classifyShape(size(value));
            end
        end

        function dimension = classifyShape(dataSize)
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

        function info = collectNested(value, path, info)
            if nargin < 3
                info = matfield.FieldRules.emptyInfo();
            end
            if isnumeric(value)
                dimension = matfield.FieldRules.classifyArray(value);
                if dimension > 0
                    info(end + 1) = matfield.FieldRules.makeInfo( ...
                        path, size(value), dimension);
                end
                return
            end
            if ~isstruct(value) || ~isscalar(value)
                return
            end

            fields = fieldnames(value);
            for fieldIndex = 1:numel(fields)
                field = fields{fieldIndex};
                childPath = field;
                if ~isempty(path)
                    childPath = [path, '.', field];
                end
                info = matfield.FieldRules.collectNested( ...
                    value.(field), childPath, info);
            end
        end

        function info = filterForOptions(info, opts)
            if matfield.FieldRules.requiresThreeDimensions(opts)
                info = info([info.Dimension] == 3);
            end
            if ~isempty(info)
                [~, order] = sort({info.Path});
                info = info(order);
            end
        end

        function tf = requiresThreeDimensions(opts)
            volumeOptionsSpecified = opts.Specified.NumIsosurfaces || ...
                opts.Specified.IsoRange || opts.Specified.IsoValues || ...
                opts.Specified.SurfaceAlpha || opts.Specified.MaxRenderSize;
            tf = (opts.Specified.PlotType && strcmp(opts.PlotType, 'volume')) || ...
                opts.Specified.Dimension || opts.Specified.Index || ...
                volumeOptionsSpecified;
        end

        function plotType = resolvePlotType(opts, fieldDimension)
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
            % UI numeric properties require double. The potentially large field
            % remains in its original numeric class.
            globalRange = double([min(fieldData(finiteMask)), ...
                max(fieldData(finiteMask))]);

            if opts.Specified.IsoValues && ...
                    (any(opts.IsoValues < globalRange(1)) || ...
                     any(opts.IsoValues > globalRange(2)))
                error('visualizeMatField:IsoValuesOutOfRange', ...
                    'Every IsoValues entry must be inside the global data range [%g, %g].', ...
                    globalRange(1), globalRange(2));
            end
        end

        function parts = parsePath(variablePath)
            variablePath = strtrim(char(string(variablePath)));
            parts = strsplit(variablePath, '.');
            if isempty(variablePath) || any(cellfun(@isempty, parts)) || ...
                    any(~cellfun(@isvarname, parts))
                error('visualizeMatField:VariablePath', ...
                    ['Variable must be a valid top-level name or a dot-separated ', ...
                     'scalar-structure field path.']);
            end
        end

        function value = traverse(value, parts, startIndex, traversed)
            for partIndex = startIndex:numel(parts)
                fieldName = parts{partIndex};
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
        end

        function dimension = requireTargetArray(value, variablePath)
            dimension = matfield.FieldRules.classifyArray(value);
            if dimension == 0
                error('visualizeMatField:NotTargetArray', ...
                    ['Variable "%s" must be a real numeric 2-D matrix or a real ', ...
                     'numeric 3-D array; got %s %s.'], ...
                    variablePath, class(value), mat2str(size(value)));
            end
        end
    end
end
