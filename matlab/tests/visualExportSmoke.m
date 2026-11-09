function visualExportSmoke
%VISUALEXPORTSMOKE Produce plot-only files for visual inspection.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    output = fullfile(root, 'artifacts', 'export');
    if ~isfolder(output), mkdir(output); end
    [a, b, c] = ndgrid(linspace(-1, 1, 35), linspace(-1, 1, 41), linspace(-1, 1, 31));
    data = single(1.00003 + .00017 * exp(-3 * (a.^2 + b.^2 + c.^2)));
    fig = visualizeMatField(data, 'Colormap', 'jet', 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    exportMatField(fig, fullfile(output, 'matlab-volume.png'), 'Width', 1200, 'Height', 900);
    mode = fig.UserData.IsoModeDropDown;
    mode.Value = 'single'; mode.ValueChangedFcn(mode, []);
    exportMatField(fig, fullfile(output, 'matlab-volume.gif'), 'Width', 640, 'Height', 480, 'Frames', 8, 'FrameRate', 5);
    mode = fig.UserData.ModeDropDown;
    mode.Value = 'slice'; mode.ValueChangedFcn(mode, []);
    exportMatField(fig, fullfile(output, 'matlab-slice.png'), 'Width', 1200, 'Height', 900);
    exportMatField(fig, fullfile(output, 'matlab-slice.gif'), 'Width', 640, 'Height', 480, 'Frames', 8, 'FrameRate', 5);
    exportMatField(fig, fullfile(output, 'matlab-slice.mat'));
    fprintf('MATLAB_EXPORT_VISUAL_OK\n');
end
