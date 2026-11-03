function tests = testColormap
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
end

function testEmptyViewerDisablesColormap(testCase)
    fig = visualizeMatField('Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    testCase.verifyTrue(isgraphics(fig.UserData.ColormapDropDown));
    testCase.verifyEqual(string(fig.UserData.ColormapDropDown.Enable), "off");
end

function testSliceChangesOnlyColors(testCase)
    a = reshape(single(1:210), [5, 6, 7]);
    fig = visualizeMatField(a, 'PlotType', 'slice', 'ColorLimits', [-1, 500], 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    image = fig.UserData.Image;
    before = image.CData;
    index = fig.UserData.Index;
    fig.UserData.Axes.XLim = [1, 3];
    fig.UserData.Axes.YLim = [2, 4];
    for name = {'jet', 'hot', 'parula'}
        selector = fig.UserData.ColormapDropDown;
        selector.Value = name{1};
        selector.ValueChangedFcn(selector, []);
        testCase.verifyEqual(colormap(fig.UserData.Axes), feval(name{1}, 256));
        testCase.verifyEqual(colormap(fig.UserData.Layout.ColorbarAxes), feval(name{1}, 256));
        testCase.verifyEqual(fig.UserData.Image, image);
        testCase.verifyEqual(image.CData, before);
        testCase.verifyEqual(fig.UserData.Index, index);
        testCase.verifyEqual(fig.UserData.Axes.CLim, [-1, 500]);
        testCase.verifyEqual(fig.UserData.Axes.XLim, [1, 3]);
        testCase.verifyEqual(fig.UserData.Axes.YLim, [2, 4]);
    end
end

function testVolumeKeepsPatchesCameraAndAlpha(testCase)
    a = reshape(single(1:210), [5, 6, 7]);
    fig = visualizeMatField(a, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    patches = fig.UserData.Patches;
    before = patches(1).FaceColor;
    vertices = patches(1).Vertices;
    camera = matfield.VolumeView.captureAxesNavigation(fig.UserData.Axes);
    limits = fig.UserData.Axes.CLim;
    alpha = patches(1).FaceAlpha;
    selector = fig.UserData.ColormapDropDown;
    selector.Value = 'hot';
    selector.ValueChangedFcn(selector, []);
    testCase.verifyEqual(fig.UserData.Patches, patches);
    testCase.verifyEqual(patches(1).Vertices, vertices);
    testCase.verifyEqual(patches(1).FaceAlpha, alpha);
    testCase.verifyNotEqual(patches(1).FaceColor, before);
    testCase.verifyEqual(colormap(fig.UserData.Axes), hot(256));
    testCase.verifyEqual(colormap(fig.UserData.Layout.ColorbarAxes), hot(256));
    testCase.verifyEqual(fig.UserData.Layout.ColorbarAxes.CLim, limits);
    testCase.verifyEqual(fig.UserData.Axes.CLim, limits);
    testCase.verifyEqual(fig.UserData.Axes.CameraPosition, camera.CameraPosition);
    testCase.verifyEqual(fig.UserData.Axes.CameraViewAngle, camera.CameraViewAngle);
    map = hot(256);
    for patch = patches(:).'
        level = getappdata(patch, 'MatfieldIsoValue');
        t = (level - limits(1)) / diff(limits);
        k = 1 + round(max(0, min(1, t)) * (size(map, 1) - 1));
        testCase.verifyEqual(patch.FaceColor, map(k, :));
    end
end

function testExplicitColormapAppliesAndLocksBothModes(testCase)
    a = reshape(single(1:210), [5, 6, 7]);
    for mode = {'slice', 'volume'}
        fig = visualizeMatField(a, 'PlotType', mode{1}, 'Colormap', 'jet', 'Visible', 'off');
        cleanup = onCleanup(@() closeViewer(fig));
        testCase.verifyEmpty(fig.UserData.ColormapDropDown);
        testCase.verifyEqual(colormap(fig.UserData.Axes), jet(256));
        close(fig);
        clear cleanup
    end
end

function testModeSubarrayAndVariableChangesKeepColormap(testCase)
    a = reshape(single(1:630), [5, 6, 7, 3]);
    fig = visualizeMatField(struct('a', a, 'b', a + 100), 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    target = fig.UserData.VariableDropDown;
    aPath = target.ItemsData{find(endsWith(target.ItemsData, '.a'), 1)};
    bPath = target.ItemsData{find(endsWith(target.ItemsData, '.b'), 1)};
    target.Value = aPath;
    target.ValueChangedFcn(target, []);
    selector = fig.UserData.ColormapDropDown;
    selector.Value = 'hot';
    selector.ValueChangedFcn(selector, []);
    matfield.Subspace.changeIndex(fig, 4, 2, true);
    testCase.verifyEqual(colormap(fig.UserData.Axes), hot(256));
    mode = fig.UserData.ModeDropDown;
    mode.Value = 'slice';
    mode.ValueChangedFcn(mode, []);
    testCase.verifyEqual(fig.UserData.ColormapDropDown.Value, 'hot');
    testCase.verifyEqual(colormap(fig.UserData.Axes), hot(256));
    target = fig.UserData.VariableDropDown;
    target.Value = bPath;
    target.ValueChangedFcn(target, []);
    testCase.verifyEqual(fig.UserData.ColormapDropDown.Value, 'hot');
end

function testUnknownColormapFailsBeforeOpeningFigure(testCase)
    before = findall(groot, 'Type', 'figure');
    testCase.verifyError(@() visualizeMatField('Colormap', 'not_a_known_colormap', 'Visible', 'off'), ...
        'visualizeMatField:InvalidColormap');
    testCase.verifyEqual(findall(groot, 'Type', 'figure'), before);
end

function closeViewer(fig)
    if isgraphics(fig), close(fig); end
end
