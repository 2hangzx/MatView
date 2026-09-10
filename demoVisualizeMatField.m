%% visualizeMatField usage examples
% Run one section at a time (Ctrl+Enter in the MATLAB Editor).
% The viewer uses one responsive shell for the source selector, plot area,
% and controls. Resizing the window reflows controls without reloading data,
% recreating the axes, or resetting the current 3-D view.

%% 0. Select a source and target variable inside the viewer
% With no positional inputs, the image starts empty. Keep the default MAT
% source and enter/browse a path, or switch the source to MATLAB Workspace.
% visualizeMatField();
%
% Name-Value options may still be fixed before choosing the file:
% visualizeMatField('PlotType', 'slice', 'Dimension', 2);

%% 0a. Direct data from a script or function-local workspace
% Passing the value is the reliable way to visualize caller-local data.
% The viewer keeps the input snapshot and never tries to revisit the caller
% from a later UI callback.
% localVolume = rand(40, 50, 60, 'single');
% visualizeMatField(localVolume);
%
% localResult = struct('flow', struct('temperature', localVolume));
% visualizeMatField(localResult);                    % choose in the UI
% visualizeMatField(localResult, 'flow.temperature'); % choose explicitly

%% 0b. Browse MATLAB Base Workspace by name
% The Refresh button explicitly rescans the Base Workspace. No background
% polling is performed.
% visualizeMatField('SourceType', 'workspace');
% visualizeMatField('SourceType', 'workspace', ...
%     'WorkspaceVariable', 'localResult.flow.temperature');

%% 1. MAT file and variable specified, all other options use defaults
% Volume mode. Use the in-window dropdown to switch modes.
matFile = fullfile(fileparts(mfilename('fullpath')), ...
    'Data', 'data_uniGrid_zFlowDirct.mat');
visualizeMatField(matFile, 'rho.rho_XYZ');

%% 1a. Specify the MAT file, then select the variable inside the viewer
% The image area starts empty and the other controls stay disabled until a
% variable is selected from the dropdown above the image.
% visualizeMatField(matFile);

%% 2. Precisely specified slice
% 'figure' is accepted as an alias of 'slice'. Dimension accepts only the
% numeric array-dimension index 1, 2, or 3.
% visualizeMatField(matFile, 'T.T_XYZ', ...
%     'PlotType', 'slice', 'Dimension', 3, 'Index', 80);

%% 3. Interactive slice with an initially selected dimension
% Dimension is fixed by the command line; index defaults to the center and
% remains editable in the figure.
% visualizeMatField(matFile, 'GD.gradNorm_XYZ', ...
%     'PlotType', 'slice', 'Dimension', 1);

%% 3a. Fixed or interactive colorbar limits
% Explicit ColorLimits fixes the range and hides the corresponding UI.
% When ColorLimits is omitted, select "指定范围" in the Slice control panel
% to enable exact lower/upper inputs and two coarse-adjustment sliders.
% Confirmed edits and slider drags update the image immediately.
% visualizeMatField(matFile, 'T.T_XYZ', ...
%     'PlotType', 'slice', 'ColorLimits', [400, 1800]);

%% 4. Three-dimensional multi-isosurface view
% visualizeMatField(matFile, 'rho.rho_XYZ', 'PlotType', 'volume');

%% 5. Tuned three-dimensional view
% visualizeMatField(matFile, 'T.gradNorm_XYZ', 'PlotType', '3d', ...
%     'NumIsosurfaces', 7, ...
%     'IsoRange', [0.10, 0.70], ...
%     'SurfaceAlpha', 0.16, ...
%     'MaxRenderSize', 110);

%% 6. Exact isosurface levels (no level controls are added to the figure)
% visualizeMatField(matFile, 'rho.rho_XYZ', 'PlotType', 'volume', ...
%     'IsoValues', [0.35, 0.60, 0.85], ...
%     'SurfaceAlpha', 0.20);

%% 7. Complete canonical syntax and another MAT file
% visualizeMatField('D:\data\another_file.mat', 'n.gradX_XYZ', ...
%     'PlotType', 'slice', ...
%     'Dimension', 2, ...
%     'Index', 60, ...
%     'ColorLimits', 'slice', ...
%     'Colormap', 'parula');

%% 8. Generic MAT layouts and two-dimensional targets
% A target may be a top-level numeric matrix or an arbitrarily nested field
% inside scalar structures. A 2-D target (including [nx, ny, 1] after
% MATLAB removes the trailing singleton dimension) is displayed directly in
% Slice mode and has no dimension/index/Volume controls.
%
% visualizeMatField('D:\data\another_file.mat', 'topLevelMatrix')
% visualizeMatField('D:\data\another_file.mat', ...
%     'caseA.flow.temperature', 'PlotType', 'slice')
