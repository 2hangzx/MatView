function T = exportMatStructure(matFile, outputFile)
% exportMatStructure
% Recursively inspect all variables in a MAT file, including nested structs.
%
% Example:
%   T = exportMatStructure('data.mat');
%   T = exportMatStructure('data.mat', 'mat_structure.xlsx');

    % Load MAT file
    data = load(matFile);

    % Result containers
    paths   = {};
    classes = {};
    sizes   = {};

    % Top-level variables
    names = fieldnames(data);

    for i = 1:numel(names)
        name = names{i};
        value = data.(name);

        [paths, classes, sizes] = walkVariable( ...
            value, name, paths, classes, sizes);
    end

    % Convert to table
    T = table( ...
        string(paths(:)), ...
        string(classes(:)), ...
        string(sizes(:)), ...
        'VariableNames', {'Path', 'Class', 'Size'});

    % Display
    disp(T);

    % Optional export
    if nargin >= 2 && ~isempty(outputFile)
        writetable(T, outputFile);
    end
end


function [paths, classes, sizes] = walkVariable( ...
    value, currentPath, paths, classes, sizes)

    % Record current variable/field
    paths{end+1}   = currentPath;
    classes{end+1} = class(value);
    sizes{end+1}   = mat2str(size(value));

    % ---------------------------------------------------------
    % Struct
    % ---------------------------------------------------------
    if isstruct(value)

        fields = fieldnames(value);

        % Scalar struct
        if isscalar(value)

            for k = 1:numel(fields)

                fieldName = fields{k};
                child = value.(fieldName);

                childPath = sprintf('%s.%s', ...
                    currentPath, fieldName);

                [paths, classes, sizes] = walkVariable( ...
                    child, childPath, ...
                    paths, classes, sizes);
            end

        % Struct array
        else

            for idx = 1:numel(value)

                elementPath = sprintf('%s(%d)', ...
                    currentPath, idx);

                for k = 1:numel(fields)

                    fieldName = fields{k};
                    child = value(idx).(fieldName);

                    childPath = sprintf('%s.%s', ...
                        elementPath, fieldName);

                    [paths, classes, sizes] = walkVariable( ...
                        child, childPath, ...
                        paths, classes, sizes);
                end
            end
        end
    end
end