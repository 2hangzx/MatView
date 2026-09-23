classdef MemorySource
    %MEMORYSOURCE Discover and load arrays passed directly by the caller.
    methods (Static)
        function targetInfo = listTargets(rootValue, rootName, opts)
            targetInfo = matfield.FieldRules.emptyInfo();
            if isnumeric(rootValue)
                dimension = matfield.FieldRules.classifyArray(rootValue);
                if dimension > 0
                    targetInfo = matfield.FieldRules.makeInfo( ...
                        rootName, size(rootValue), dimension);
                end
            elseif isstruct(rootValue) && isscalar(rootValue)
                targetInfo = matfield.FieldRules.collectNested( ...
                    rootValue, rootName, targetInfo);
            end
            targetInfo = matfield.FieldRules.filterForOptions(targetInfo, opts);
        end

        function [value, fieldDimension, canonicalPath] = ...
                loadTarget(rootValue, rootName, variablePath)
            if isnumeric(rootValue)
                requestedPath = strtrim(char(string(variablePath)));
                if ~isempty(requestedPath) && ~strcmp(requestedPath, rootName)
                    error('visualizeMatField:MemoryArrayHasNoFields', ...
                        'Direct numeric input "%s" has no nested target "%s".', ...
                        rootName, requestedPath);
                end
                canonicalPath = rootName;
                value = rootValue;
            else
                parts = matfield.FieldRules.parsePath(variablePath);
                startIndex = 1;
                canonicalPath = strjoin(parts, '.');
                if strcmp(parts{1}, rootName)
                    startIndex = 2;
                else
                    canonicalPath = [rootName, '.', canonicalPath];
                end
                value = matfield.FieldRules.traverse( ...
                    rootValue, parts, startIndex, rootName);
            end
            fieldDimension = matfield.FieldRules.requireTargetArray( ...
                value, canonicalPath);
        end
    end
end
