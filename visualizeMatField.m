function fig = visualizeMatField(varargin)
%VISUALIZEMATFIELD Interactively inspect a 2-D or 3-D numeric MAT variable.
%
% Basic usage
%   visualizeMatField()
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat')
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'rho.rho_XYZ')
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'T.T_XYZ', ...
%       'PlotType', 'slice', 'Dimension', 3, 'Index', 80)
%   visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', ...
%       'rho.gradNorm_XYZ', 'PlotType', 'volume')
%
% Plot types
%   slice  - A single array plane. 'figure' is accepted as an alias. The
%            dimension, index and color scaling remain editable.
%   volume - Multiple translucent isosurfaces (the 3-D counterpart of a
%            contour plot). The number/range/opacity can be edited.
%   If PlotType is omitted, it can be changed from inside the viewer.
%
% Positional input
%   matFile           Optional first positional argument: MAT-file path. If
%                     omitted, enter a path or browse for a file in the UI.
%   variablePath      Optional second positional argument: dot-separated
%                     path to a real numeric 2-D/3-D array. Top-level and
%                     arbitrarily nested scalar-struct fields are accepted.
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

    opts = matfield.Input.parse(varargin);
    if opts.Specified.MatFile
        opts.MatFile = matfield.Data.resolveMatFile(opts.MatFile);
    end

    if ~opts.Specified.Variable
        variableInfo = matfield.Data.emptyVariableInfo();
        if opts.Specified.MatFile
            variableInfo = matfield.Data.listSelectableVariables(opts.MatFile, opts);
        end
        opts.AvailableVariables = {variableInfo.Path};
        opts.AvailableVariableInfo = variableInfo;
        if opts.Specified.MatFile && isempty(opts.AvailableVariables)
            error('visualizeMatField:NoSelectableVariables', ...
                ['The MAT file contains no compatible real numeric 2-D/3-D ', ...
                 'arrays for the requested plotting options.']);
        end
        fig = matfield.SelectionView.createVariableSelectionFigure(opts);
        return
    end

    [fieldData, resolvedFile, fieldDimension] = ...
        matfield.Data.loadTargetArray(opts.MatFile, opts.Variable);
    opts.FieldDimension = fieldDimension;
    opts.PlotType = matfield.Data.resolvePlotTypeForField(opts, fieldDimension);
    globalRange = matfield.Data.validateLoadedArray(fieldData, opts);

    opts.MatFile = resolvedFile;
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
