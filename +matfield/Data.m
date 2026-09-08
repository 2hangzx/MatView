classdef Data
    %DATA Discover, classify, load, and validate MAT-file field data.
    methods (Static)
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
            variableInfo = matfield.Data.emptyVariableInfo();
        
            % Version 7.3 MAT files are HDF5 containers. Walk group/dataset
            % metadata recursively so large arrays are not loaded just to build the
            % selector. MATLAB's internal #refs# storage is deliberately skipped.
            try
                fileInfo = h5info(matFile);
                variableInfo = matfield.Data.collectHdf5Variables(fileInfo, variableInfo);
            catch
                % Earlier MAT formats are not HDF5. Top-level numeric arrays can be
                % classified from WHOS metadata; scalar structs are then loaded one
                % at a time and recursively inspected.
                topInfo = whos('-file', matFile);
                for rootIndex = 1:numel(topInfo)
                    item = topInfo(rootIndex);
                    if matfield.Data.isNumericClassName(item.class)
                        isComplex = isfield(item, 'complex') && item.complex;
                        dimension = matfield.Data.classifyTargetShape(item.size);
                        if ~isComplex && dimension > 0
                            variableInfo(end + 1) = matfield.Data.makeVariableInfo( ...
                                item.name, item.size, dimension); %#ok<AGROW>
                        end
                    elseif strcmp(item.class, 'struct') && isequal(item.size, [1, 1])
                        loaded = load(matFile, item.name);
                        variableInfo = matfield.Data.collectClassicVariables(loaded.(item.name), ...
                            item.name, variableInfo);
                        clear loaded
                    end
                end
            end
        
            if matfield.Data.requiresThreeDimensions(opts)
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
                    ~strcmp(matfield.Data.hdf5AttributeText(group.Attributes, 'MATLAB_class'), 'struct')
                % Only scalar-struct groups form valid dot-separated MATLAB paths.
                % This prevents datasets internal to objects/tables from appearing
                % as selectable arrays merely because their HDF5 storage is numeric.
                return
            end
        
            groupPath = regexprep(group.Name, '^/', '');
            groupPath = strrep(groupPath, '/', '.');
            for datasetIndex = 1:numel(group.Datasets)
                dataset = group.Datasets(datasetIndex);
                matlabClass = matfield.Data.hdf5AttributeText(dataset.Attributes, 'MATLAB_class');
                if ~matfield.Data.isNumericClassName(matlabClass) || ...
                        ~any(strcmp(dataset.Datatype.Class, {'H5T_FLOAT', 'H5T_INTEGER'}))
                    continue
                end
                dimension = matfield.Data.classifyTargetShape(dataset.Dataspace.Size);
                if dimension == 0
                    continue
                end
                if isempty(groupPath)
                    path = dataset.Name;
                else
                    path = [groupPath, '.', dataset.Name];
                end
                info(end + 1) = matfield.Data.makeVariableInfo( ...
                    path, dataset.Dataspace.Size, dimension); %#ok<AGROW>
            end
        
            for groupIndex = 1:numel(group.Groups)
                info = matfield.Data.collectHdf5Variables(group.Groups(groupIndex), info);
            end
        end

        function info = collectClassicVariables(value, path, info)
            if isnumeric(value)
                dimension = matfield.Data.classifyTargetArray(value);
                if dimension > 0
                    info(end + 1) = matfield.Data.makeVariableInfo(path, size(value), dimension);
                end
                return
            end
            if ~isstruct(value) || ~isscalar(value)
                return
            end
        
            fields = fieldnames(value);
            for fieldIndex = 1:numel(fields)
                field = fields{fieldIndex};
                info = matfield.Data.collectClassicVariables(value.(field), ...
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
                dimension = matfield.Data.classifyTargetShape(size(value));
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
            resolvedFile = matfield.Data.resolveMatFile(matFile);
        
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
        
            fieldDimension = matfield.Data.classifyTargetArray(value);
            if fieldDimension == 0
                error('visualizeMatField:NotTargetArray', ...
                    ['Variable "%s" must be a real numeric 2-D matrix or a real ', ...
                     'numeric 3-D array; got %s %s.'], ...
                    variablePath, class(value), mat2str(size(value)));
            end
        end

    end
end
