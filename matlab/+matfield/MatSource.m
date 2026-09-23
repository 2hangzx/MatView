classdef MatSource
    %MATSOURCE Discover and load drawable variables stored in MAT files.
    methods (Static)
        function resolvedFile = resolveFile(matFile)
            candidate = strtrim(char(matFile));
            if isempty(candidate)
                error('visualizeMatField:EmptyFile', 'MatFile cannot be empty.');
            end
            fileObject = java.io.File(candidate);
            if ~fileObject.isAbsolute()
                candidate = fullfile(pwd, candidate);
                fileObject = java.io.File(candidate);
            end
            if ~isfile(candidate)
                error('visualizeMatField:FileNotFound', ...
                    'MAT file was not found: %s', matFile);
            end
            resolvedFile = char(fileObject.getCanonicalPath());
        end

        function variableInfo = listTargets(matFile, opts)
            variableInfo = matfield.FieldRules.emptyInfo();
            try
                fileInfo = h5info(matFile);
                variableInfo = matfield.MatSource.collectHdf5Variables( ...
                    fileInfo, variableInfo);
            catch
                topInfo = whos('-file', matFile);
                for rootIndex = 1:numel(topInfo)
                    item = topInfo(rootIndex);
                    if matfield.FieldRules.isNumericClassName(item.class)
                        isComplex = isfield(item, 'complex') && item.complex;
                        dimension = matfield.FieldRules.classifyShape(item.size);
                        if ~isComplex && dimension > 0
                            variableInfo(end + 1) = matfield.FieldRules.makeInfo( ...
                                item.name, item.size, dimension); %#ok<AGROW>
                        end
                    elseif strcmp(item.class, 'struct') && isequal(item.size, [1, 1])
                        loaded = load(matFile, item.name);
                        variableInfo = matfield.FieldRules.collectNested( ...
                            loaded.(item.name), item.name, variableInfo);
                        clear loaded
                    end
                end
            end
            variableInfo = matfield.FieldRules.filterForOptions(variableInfo, opts);
        end

        function [value, resolvedFile, fieldDimension, canonicalPath] = ...
                loadTarget(matFile, variablePath)
            resolvedFile = matfield.MatSource.resolveFile(matFile);
            parts = matfield.FieldRules.parsePath(variablePath);
            rootName = parts{1};
            rootInfo = whos('-file', resolvedFile, rootName);
            if isempty(rootInfo)
                available = whos('-file', resolvedFile);
                availableText = strjoin({available.name}, ', ');
                error('visualizeMatField:RootNotFound', ...
                    'Top-level variable "%s" was not found. Available variables: %s', ...
                    rootName, availableText);
            end

            loaded = load(resolvedFile, rootName);
            value = loaded.(rootName);
            value = matfield.FieldRules.traverse(value, parts, 2, rootName);
            canonicalPath = strjoin(parts, '.');
            fieldDimension = matfield.FieldRules.requireTargetArray( ...
                value, canonicalPath);
        end

        function info = collectHdf5Variables(group, info)
            if startsWith(group.Name, '/#refs#')
                return
            end
            if ~strcmp(group.Name, '/') && ...
                    ~strcmp(matfield.MatSource.hdf5AttributeText( ...
                    group.Attributes, 'MATLAB_class'), 'struct')
                return
            end

            groupPath = regexprep(group.Name, '^/', '');
            groupPath = strrep(groupPath, '/', '.');
            for datasetIndex = 1:numel(group.Datasets)
                dataset = group.Datasets(datasetIndex);
                matlabClass = matfield.MatSource.hdf5AttributeText( ...
                    dataset.Attributes, 'MATLAB_class');
                if ~matfield.FieldRules.isNumericClassName(matlabClass) || ...
                        ~any(strcmp(dataset.Datatype.Class, ...
                        {'H5T_FLOAT', 'H5T_INTEGER'}))
                    continue
                end
                dimension = matfield.FieldRules.classifyShape(dataset.Dataspace.Size);
                if dimension == 0
                    continue
                end
                if isempty(groupPath)
                    path = dataset.Name;
                else
                    path = [groupPath, '.', dataset.Name];
                end
                info(end + 1) = matfield.FieldRules.makeInfo( ...
                    path, dataset.Dataspace.Size, dimension); %#ok<AGROW>
            end

            for groupIndex = 1:numel(group.Groups)
                info = matfield.MatSource.collectHdf5Variables( ...
                    group.Groups(groupIndex), info);
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
    end
end
