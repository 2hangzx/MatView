function fig = visualizeMatField(varargin)
%VISUALIZEMATFIELD Interactively inspect a 2-D or 3-D numeric field.
%
% Basic usage
%   visualizeMatField()
%   visualizeMatField('../Data/data_uniGrid_zFlowDirct.mat')
%   visualizeMatField('../Data/data_uniGrid_zFlowDirct.mat', 'rho.rho_XYZ')
%   visualizeMatField('../Data/data_uniGrid_zFlowDirct.mat', 'T.T_XYZ', ...
%       'PlotType', 'slice', 'Dimension', 3, 'Index', 80)
%   visualizeMatField('../Data/data_uniGrid_zFlowDirct.mat', ...
%       'rho.gradNorm_XYZ', 'PlotType', 'volume')
%   visualizeMatField(workspaceArray)
%   visualizeMatField(workspaceStruct, 'flow.temperature')
%   visualizeMatField('SourceType', 'workspace')
%   visualizeMatField('SourceType', 'workspace', ...
%       'WorkspaceVariable', 'flow.temperature')
%
% Plot types
%   slice  - A single array plane. 'figure' is accepted as an alias. The
%            dimension, index and color scaling remain editable.
%   volume - Multiple translucent isosurfaces (the 3-D counterpart of a
%            contour plot). The number/range/opacity can be edited.
%   If PlotType is omitted, it can be changed from inside the viewer.
%
% Positional input
%   source            Optional first positional input: a MAT-file path, a
%                     numeric array, or a scalar structure. Local/caller
%                     variables are supported by passing their values here.
%   variablePath      Optional second positional argument: dot-separated
%                     path to a real numeric 2-D/3-D array. Top-level and
%                     nested scalar-struct fields are accepted. A direct
%                     numeric source does not need this argument.
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
%   SourceType        'matfile' (default UI source), 'workspace', or
%                     'memory'. Memory is normally inferred from direct data.
%   WorkspaceVariable  Base Workspace variable/field path. Valid only when
%                     SourceType is explicitly 'workspace'.
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

    sourceInputName = '';
    if nargin >= 1
        sourceInputName = inputname(1);
    end
    opts = matfield.Input.parse(varargin, sourceInputName);
    opts.Source = matfield.Data.resolve(opts.Source);
    if strcmp(opts.Source.Type, 'matfile')
        opts.MatFile = opts.Source.Location;
    end
    if strcmp(opts.Source.Type, 'workspace')
        workspaceInfo = matfield.Data.listTargets(opts.Source, opts);
        opts.AvailableVariables = {workspaceInfo.Path};
        opts.AvailableVariableInfo = workspaceInfo;
    end

    if ~opts.Specified.Variable
        if isfield(opts, 'AvailableVariableInfo')
            variableInfo = opts.AvailableVariableInfo;
        else
            variableInfo = matfield.Data.emptyVariableInfo();
        end
        if matfield.Data.isReady(opts.Source) && ...
                ~isfield(opts, 'AvailableVariableInfo')
            variableInfo = matfield.Data.listTargets(opts.Source, opts);
        end
        opts.AvailableVariables = {variableInfo.Path};
        opts.AvailableVariableInfo = variableInfo;
        if isempty(opts.AvailableVariables) && ...
                any(strcmp(opts.Source.Type, {'matfile', 'memory'})) && ...
                matfield.Data.isReady(opts.Source)
            error('visualizeMatField:NoSelectableVariables', ...
                ['The selected data source contains no compatible real ', ...
                 'numeric 2-D/3-D arrays for the requested plotting options.']);
        end
        fig = matfield.SelectionView.createVariableSelectionFigure(opts);
        return
    end

    [fieldData, opts.Source, fieldDimension, canonicalPath] = ...
        matfield.Data.loadTarget(opts.Source, opts.Variable);
    opts.Variable = canonicalPath;
    opts.FieldDimension = fieldDimension;
    opts.PlotType = matfield.Data.resolvePlotTypeForField(opts, fieldDimension);
    globalRange = matfield.Data.validateLoadedArray(fieldData, opts);

    if strcmp(opts.Source.Type, 'matfile')
        opts.MatFile = opts.Source.Location;
    else
        opts.MatFile = '';
    end
    if fieldDimension == 3
        opts.Dimension = matfield.Input.normalizeDimension(opts.Dimension);
        matfield.Input.validateInitialIndex(opts.Index, opts.Dimension, size(fieldData));
    end

    switch opts.PlotType
        case 'slice'
            fig = matfield.SliceView.createSliceFigure(fieldData, opts, globalRange);
        case 'volume'
            fig = matfield.VolumeView.createVolumeFigure(fieldData, opts, globalRange);
        otherwise
            error('visualizeMatField:InternalPlotType', ...
                'Unsupported normalized plot type "%s".', opts.PlotType);
    end
end
