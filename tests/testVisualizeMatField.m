function tests = testVisualizeMatField
%TESTVISUALIZEMATFIELD Regression coverage for the public viewer workflow.
    tests = functiontests(localfunctions);
end


function setupOnce(testCase)
    projectRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(projectRoot);

    matFile = [tempname, '.mat'];
    matrix2d = reshape(single(1:30), [5, 6]);
    volume3d = reshape(single(1:120), [4, 5, 6]);
    nested = struct('volume', volume3d);
    ignoredVector = 1:8;
    save(matFile, 'matrix2d', 'volume3d', 'nested', 'ignoredVector');

    testCase.TestData.ProjectRoot = projectRoot;
    testCase.TestData.MatFile = matFile;
end


function teardownOnce(testCase)
    if isfile(testCase.TestData.MatFile)
        delete(testCase.TestData.MatFile);
    end
end


function testEmptyFileSelectionState(testCase)
    fig = visualizeMatField('Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEmpty(fig.UserData.MatFile);
    testCase.verifyEqual(fig.UserData.Variable, '');
    testCase.verifyEqual(string(fig.UserData.VariableDropDown.Enable), "off");
    testCase.verifyEqual(string(fig.UserData.Axes.Visible), "off");
end


function testVariableSelectionLoadsWithoutExtraRedrawButton(testCase)
    fig = visualizeMatField(testCase.TestData.MatFile, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    selector = fig.UserData.VariableDropDown;
    testCase.verifyEqual(string(selector.Enable), "on");
    selector.Value = 'nested.volume';
    selector.ValueChangedFcn(selector, []);

    testCase.verifyEqual(fig.UserData.Variable, 'nested.volume');
    testCase.verifyEqual(fig.UserData.PlotMode, 'volume');
    testCase.verifyEqual(class(fig.UserData.Data), 'single');
end


function testTwoDimensionalFieldUsesSliceOnly(testCase)
    fig = visualizeMatField(testCase.TestData.MatFile, 'matrix2d', ...
        'PlotType', 'slice', 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEqual(fig.UserData.FieldDimension, 2);
    testCase.verifyEqual(fig.UserData.PlotMode, 'slice');
    testCase.verifyEmpty(fig.UserData.Dimension);
    testCase.verifyEqual(class(fig.UserData.Data), 'single');
    testCase.verifyTrue(isgraphics(fig.UserData.Image));
    testCase.verifyTrue(isgraphics(fig.UserData.Colorbar));
end


function testThreeDimensionalSliceParameters(testCase)
    fig = visualizeMatField(testCase.TestData.MatFile, 'volume3d', ...
        'PlotType', 'slice', 'Dimension', 2, 'Index', 3, ...
        'ColorLimits', [10, 100], 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEqual(fig.UserData.Dimension, 2);
    testCase.verifyEqual(fig.UserData.Index, 3);
    testCase.verifyEqual(fig.UserData.Axes.CLim, [10, 100]);
end


function testVolumeRenderingAndModeSwitch(testCase)
    fig = visualizeMatField(testCase.TestData.MatFile, 'volume3d', ...
        'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEqual(fig.UserData.PlotMode, 'volume');
    testCase.verifyNotEmpty(fig.UserData.Patches);
    testCase.verifyTrue(isgraphics(fig.UserData.Colorbar));

    modeSelector = fig.UserData.ModeDropDown;
    modeSelector.Value = 'slice';
    modeSelector.ValueChangedFcn(modeSelector, []);
    testCase.verifyEqual(fig.UserData.PlotMode, 'slice');

    modeSelector = fig.UserData.ModeDropDown;
    modeSelector.Value = 'volume';
    modeSelector.ValueChangedFcn(modeSelector, []);
    testCase.verifyEqual(fig.UserData.PlotMode, 'volume');
    testCase.verifyNotEmpty(fig.UserData.Patches);
end


function testResponsiveLayoutProfiles(testCase)
    fig = visualizeMatField(testCase.TestData.MatFile, 'volume3d', ...
        'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    fig.Position(3) = 900;
    matfield.Layout.applyResponsiveViewerLayout(fig, true);
    testCase.verifyEqual(fig.UserData.Layout.Profile, 'compact');

    fig.Position(3) = 650;
    matfield.Layout.applyResponsiveViewerLayout(fig, true);
    testCase.verifyEqual(fig.UserData.Layout.Profile, 'narrow');
end


function testViewOwnedPlaybackFrameAdvance(testCase)
    sliceFig = visualizeMatField(testCase.TestData.MatFile, 'volume3d', ...
        'PlotType', 'slice', 'Dimension', 3, 'Visible', 'off');
    sliceCleanup = onCleanup(@() closeViewer(sliceFig));
    initialIndex = sliceFig.UserData.Index;
    matfield.SliceView.advancePlayback(sliceFig, [], []);
    testCase.verifyEqual(sliceFig.UserData.Index, initialIndex + 1);
    closeViewer(sliceFig);
    clear sliceCleanup

    volumeFig = visualizeMatField(testCase.TestData.MatFile, 'volume3d', ...
        'PlotType', 'volume', 'Visible', 'off');
    volumeCleanup = onCleanup(@() closeViewer(volumeFig));
    isoMode = volumeFig.UserData.IsoModeDropDown;
    isoMode.Value = 'single';
    isoMode.ValueChangedFcn(isoMode, []);
    initialValue = volumeFig.UserData.ExactIsoValue;
    matfield.VolumeView.advancePlayback(volumeFig, [], []);
    testCase.verifyGreaterThan(volumeFig.UserData.ExactIsoValue, initialValue);
    clear volumeCleanup
end


function closeViewer(fig)
    if isgraphics(fig)
        close(fig);
    end
end
