classdef Data
    %DATA Dispatch target discovery and loading to the active data source.
    methods (Static)
        function source = makeSource(sourceType, location, rootValue, rootName)
            if nargin < 2
                location = '';
            end
            if nargin < 3
                rootValue = [];
            end
            if nargin < 4
                rootName = '';
            end
            source = struct( ...
                'Type', char(sourceType), ...
                'Location', char(location), ...
                'RootValue', rootValue, ...
                'RootName', char(rootName), ...
                'DisplayName', '');
            switch source.Type
                case 'matfile'
                    source.DisplayName = source.Location;
                case 'workspace'
                    source.Location = 'base';
                    source.DisplayName = 'Base Workspace';
                case 'memory'
                    source.DisplayName = source.RootName;
                otherwise
                    error('visualizeMatField:InternalSourceType', ...
                        'Unsupported data source type "%s".', source.Type);
            end
        end

        function tf = isReady(source)
            switch source.Type
                case 'matfile'
                    tf = ~isempty(source.Location);
                case {'workspace', 'memory'}
                    tf = true;
                otherwise
                    tf = false;
            end
        end

        function source = resolve(source)
            if strcmp(source.Type, 'matfile') && ~isempty(source.Location)
                source.Location = matfield.MatSource.resolveFile(source.Location);
                source.DisplayName = source.Location;
            end
        end

        function targetInfo = listTargets(source, opts)
            if ~matfield.Data.isReady(source)
                targetInfo = matfield.FieldRules.emptyInfo();
                return
            end
            switch source.Type
                case 'matfile'
                    targetInfo = matfield.MatSource.listTargets( ...
                        source.Location, opts);
                case 'workspace'
                    targetInfo = matfield.WorkspaceSource.listTargets(opts);
                case 'memory'
                    targetInfo = matfield.MemorySource.listTargets( ...
                        source.RootValue, source.RootName, opts);
                otherwise
                    error('visualizeMatField:InternalSourceType', ...
                        'Unsupported data source type "%s".', source.Type);
            end
        end

        function [value, source, fieldDimension, canonicalPath] = ...
                loadTarget(source, variablePath)
            switch source.Type
                case 'matfile'
                    [value, resolvedFile, fieldDimension, canonicalPath] = ...
                        matfield.MatSource.loadTarget( ...
                        source.Location, variablePath);
                    source.Location = resolvedFile;
                    source.DisplayName = resolvedFile;
                case 'workspace'
                    [value, fieldDimension, canonicalPath] = ...
                        matfield.WorkspaceSource.loadTarget(variablePath);
                case 'memory'
                    [value, fieldDimension, canonicalPath] = ...
                        matfield.MemorySource.loadTarget( ...
                        source.RootValue, source.RootName, variablePath);
                otherwise
                    error('visualizeMatField:InternalSourceType', ...
                        'Unsupported data source type "%s".', source.Type);
            end
        end

        function text = tooltip(source)
            switch source.Type
                case 'matfile'
                    text = source.Location;
                case 'workspace'
                    text = 'MATLAB Base Workspace（点击刷新后重新读取）';
                case 'memory'
                    text = sprintf('调用时传入的内存变量：%s', source.RootName);
                otherwise
                    text = '';
            end
        end

        function info = emptyVariableInfo()
            info = matfield.FieldRules.emptyInfo();
        end

        function plotType = resolvePlotTypeForField(opts, fieldDimension)
            plotType = matfield.FieldRules.resolvePlotType(opts, fieldDimension);
        end

        function globalRange = validateLoadedArray(fieldData, opts)
            globalRange = matfield.FieldRules.validateLoadedArray(fieldData, opts);
        end

        function resolvedFile = resolveMatFile(matFile)
            resolvedFile = matfield.MatSource.resolveFile(matFile);
        end
    end
end
