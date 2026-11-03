function visualSubspaceSmoke
%VISUALSUBSPACESMOKE Export actual N-D viewer windows for layout inspection.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    output = fullfile(root, 'artifacts');
    if ~isfolder(output), mkdir(output); end
    [d1, d2, d3] = ndgrid(linspace(-1, 1, 35), linspace(-1, 1, 43), linspace(-1, 1, 31));
    field = exp(-3 * (d1.^2 + d2.^2 + d3.^2));
    a = single(cat(4, field, d1 .* field, d2 .* field));
    fig = visualizeMatField(a);
    cleanup = onCleanup(@() close(fig));
    matfield.Subspace.changeIndex(fig, 4, 2, true);
    assert(isequal(fig.UserData.Data, a(:, :, :, 2)));
    drawnow;
    exportapp(fig, fullfile(output, 'nd-volume-wide.png'));
    mode = fig.UserData.ModeDropDown;
    mode.Value = 'slice';
    mode.ValueChangedFcn(mode, []);
    drawnow;
    exportapp(fig, fullfile(output, 'nd-slice-wide.png'));
    fig.Position(3:4) = [650, 800];
    matfield.Layout.applyResponsiveViewerLayout(fig, true);
    drawnow;
    exportapp(fig, fullfile(output, 'nd-slice-narrow.png'));
    state = fig.UserData;
    canvas = getpixelposition(state.Layout.PlotCanvas);
    bar = state.Colorbar.Position;
    box = state.Axes.OuterPosition;
    assert(state.Layout.ColorbarPanel.Position(1) >= box(1) + box(3));
    assert(bar(1) + bar(3) + 60 < state.Layout.ColorbarPanel.Position(3));
    assert(bar(2) > 0 && bar(2) + bar(4) < canvas(4));
    fprintf('NARROW canvas=%s axes=%s colorbar=%s\n', mat2str(canvas), mat2str(box), mat2str(bar));
    fprintf('MATLAB_ND_VISUAL_SMOKE_OK\n');
end
