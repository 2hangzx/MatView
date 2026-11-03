function visualColormapSmoke
%VISUALCOLORMAPSMOKE Export two/three-dimensional colormap selections.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    output = fullfile(root, 'artifacts');
    if ~isfolder(output), mkdir(output); end
    [d1, d2, d3] = ndgrid(linspace(-1, 1, 35), linspace(-1, 1, 43), linspace(-1, 1, 31));
    a = single(exp(-3 * (d1.^2 + d2.^2 + d3.^2)));
    fig = visualizeMatField(cat(4, a, 2*a));
    cleanup = onCleanup(@() close(fig));
    for name = {'jet', 'hot'}
        selector = fig.UserData.ColormapDropDown;
        selector.Value = name{1};
        selector.ValueChangedFcn(selector, []);
        drawnow;
        pause(0.25);
        drawnow;
        exportapp(fig, fullfile(output, ['colormap-', name{1}, '-volume.png']));
    end
    mode = fig.UserData.ModeDropDown;
    mode.Value = 'slice';
    mode.ValueChangedFcn(mode, []);
    drawnow;
    pause(0.25);
    drawnow;
    exportapp(fig, fullfile(output, 'colormap-hot-slice.png'));
    fig.Position(3:4) = [650, 800];
    matfield.Layout.applyResponsiveViewerLayout(fig, true);
    drawnow;
    pause(0.25);
    drawnow;
    exportapp(fig, fullfile(output, 'colormap-hot-slice-narrow.png'));
    state = fig.UserData;
    bounds = getpixelposition(state.Layout.PlotCanvas);
    fprintf('Canvas=%s Colorbar=%s Location=%s\n', mat2str(bounds), ...
        mat2str(state.Colorbar.Position), state.Colorbar.Location);
    assert(state.Layout.ColorbarPanel.Position(1) >= ...
        state.Axes.OuterPosition(1) + state.Axes.OuterPosition(3));
    fprintf('MATLAB_COLORMAP_VISUAL_SMOKE_OK\n');
end
