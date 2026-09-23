classdef WorkspaceSource
    %WORKSPACESOURCE Browse and read variables from MATLAB Base Workspace.
    methods (Static)
        function targetInfo = listTargets(opts)
            targetInfo = matfield.FieldRules.emptyInfo();
            topInfo = evalin('base', 'whos');
            for rootIndex = 1:numel(topInfo)
                item = topInfo(rootIndex);
                if matfield.FieldRules.isNumericClassName(item.class)
                    isComplex = isfield(item, 'complex') && item.complex;
                    dimension = matfield.FieldRules.classifyShape(item.size);
                    if ~isComplex && dimension > 0
                        targetInfo(end + 1) = matfield.FieldRules.makeInfo( ...
                            item.name, item.size, dimension); %#ok<AGROW>
                    end
                elseif strcmp(item.class, 'struct') && isequal(item.size, [1, 1])
                    rootValue = evalin('base', item.name);
                    targetInfo = matfield.FieldRules.collectNested( ...
                        rootValue, item.name, targetInfo);
                    clear rootValue
                end
            end
            targetInfo = matfield.FieldRules.filterForOptions(targetInfo, opts);
        end

        function [value, fieldDimension, canonicalPath] = loadTarget(variablePath)
            parts = matfield.FieldRules.parsePath(variablePath);
            rootName = parts{1};
            topInfo = evalin('base', 'whos');
            if ~any(strcmp({topInfo.name}, rootName))
                error('visualizeMatField:WorkspaceVariableNotFound', ...
                    'Variable "%s" no longer exists in the Base Workspace.', rootName);
            end
            value = evalin('base', rootName);
            value = matfield.FieldRules.traverse(value, parts, 2, rootName);
            canonicalPath = strjoin(parts, '.');
            fieldDimension = matfield.FieldRules.requireTargetArray( ...
                value, canonicalPath);
        end
    end
end
