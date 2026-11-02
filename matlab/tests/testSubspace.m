function tests = testSubspace
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    a = reshape(single(1:576), [4, 6, 8, 3]);
    nested = struct('field', a);
    paths = {[tempname, '.mat'], [tempname, '.mat']};
    save(paths{1}, 'a', 'nested', '-v7');
    save(paths{2}, 'a', 'nested', '-v7.3');
    testCase.TestData.A = a;
    testCase.TestData.Paths = paths;
    testCase.TestData.BaseName = ['vmfND', erase(char(java.util.UUID.randomUUID), '-')];
end

function teardownOnce(testCase)
    for path = testCase.TestData.Paths
        delete(path{1});
    end
    evalin('base', ['clear ', testCase.TestData.BaseName]);
end

function testClassificationAndInvalidSelections(testCase)
    testCase.verifyEqual(matfield.FieldRules.classifyShape([4, 6, 8, 3]), 0);
    testCase.verifyEqual(matfield.FieldRules.classifySourceShape([4, 6, 8, 3]), 4);
    testCase.verifyEqual(matfield.FieldRules.classifySourceShape([1, 4, 6, 8]), 4);
    testCase.verifyEqual(matfield.FieldRules.classifySourceShape([1, 4, 6]), 0);
    testCase.verifyError(@() matfield.Subspace.selectShape([4, 6, 8, 3], [3, 2, 1], []), ...
        'visualizeMatField:InvalidSubspace');
    testCase.verifyError(@() matfield.Subspace.selectShape([4, 6, 8, 3], [1, 2, 3], [4, 4]), ...
        'visualizeMatField:ExtraIndexOutOfRange');
    testCase.verifyError(@() matfield.Subspace.selectShape([4, 6, 8, 3], [1, 2, 3], [2, 1]), ...
        'visualizeMatField:ExtraIndexOutOfRange');
end

function testDefaultMemorySubarray(testCase)
    a = testCase.TestData.A;
    fig = visualizeMatField(a, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    testCase.verifyEqual(fig.UserData.Data, a(:, :, :, 1));
    testCase.verifyEqual(class(fig.UserData.Data), 'single');
    testCase.verifyEqual(fig.UserData.Options.Subspace.RetainedDimensions, [1, 2, 3]);
    testCase.verifyEqual(fig.UserData.Options.Subspace.ExtraIndices, [4, 1]);
    testCase.verifyTrue(isgraphics(fig.UserData.SubspaceControls.Panel));
    testCase.verifyNotEmpty(fig.UserData.Patches);
end

function testSwitchExtraIndexKeepsCamera(testCase)
    a = testCase.TestData.A;
    fig = visualizeMatField(a, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    camera = matfield.VolumeView.captureAxesNavigation(fig.UserData.Axes);
    edit = fig.UserData.SubspaceControls.Edits(1);
    edit.Value = 2;
    edit.ValueChangedFcn(edit, []);
    testCase.verifyEqual(fig.UserData.Data, a(:, :, :, 2));
    testCase.verifyEqual(fig.UserData.GlobalRange, double([193, 384]));
    testCase.verifyEqual(fig.UserData.Axes.CameraPosition, camera.CameraPosition, 'AbsTol', 1e-9);
    testCase.verifyEqual(fig.UserData.Axes.CameraViewAngle, camera.CameraViewAngle, 'AbsTol', 1e-9);
    testCase.verifyEqual(fig.UserData.SubspaceControls.Sliders(1).Value, 2);
    testCase.verifyTrue(contains(fig.UserData.SubspaceControls.Summary.Text, 'Dim 4=2'));
end

function testSwitchSingleIsoUpdatesLimits(testCase)
    fig = visualizeMatField(testCase.TestData.A, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    isoMode = fig.UserData.IsoModeDropDown;
    isoMode.Value = 'single';
    isoMode.ValueChangedFcn(isoMode, []);
    edit = fig.UserData.SubspaceControls.Edits(1);
    edit.Value = 3;
    edit.ValueChangedFcn(edit, []);
    testCase.verifyEqual(fig.UserData.IsoSelectionMode, 'single');
    testCase.verifyEqual(fig.UserData.ExactValueSlider.Limits, [385, 576]);
    testCase.verifyGreaterThanOrEqual(fig.UserData.ExactIsoValue, 385);
end

function testRetainedDimensionsAndOriginalAxisLabels(testCase)
    a = testCase.TestData.A;
    fig = visualizeMatField(a, 'RetainedDimensions', [1, 3, 4], ...
        'ExtraIndices', [2, 3], 'PlotType', 'slice', 'Dimension', 4, 'Index', 2, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    testCase.verifyEqual(fig.UserData.Data, reshape(a(:, 3, :, :), [4, 8, 3]));
    testCase.verifyEqual(fig.UserData.Dimension, 3);
    testCase.verifyEqual(fig.UserData.Axes.XLabel.String, 'Dim 1 index');
    testCase.verifyEqual(fig.UserData.Axes.YLabel.String, 'Dim 3 index');
    testCase.verifyTrue(contains(fig.UserData.Axes.Title.String, 'Dim 4 = 2'));
    testCase.verifyEqual(fig.UserData.SubspaceControls.RetainedEdit.Editable, matlab.lang.OnOffSwitchState.off);
    testCase.verifyEqual(fig.UserData.SubspaceControls.Edits(1).Enable, matlab.lang.OnOffSwitchState.off);
end

function testRetainedEditChangesToTwoDimensions(testCase)
    a = testCase.TestData.A;
    fig = visualizeMatField(a, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    edit = fig.UserData.SubspaceControls.RetainedEdit;
    edit.Value = '2, 4';
    edit.ValueChangedFcn(edit, []);
    testCase.verifyEqual(fig.UserData.FieldDimension, 2);
    testCase.verifyEqual(fig.UserData.PlotMode, 'slice');
    testCase.verifyEqual(fig.UserData.Data, reshape(a(1, :, 1, :), [6, 3]));
    testCase.verifyEqual(fig.UserData.Axes.XLabel.String, 'Dim 2 index');
    testCase.verifyEqual(fig.UserData.Axes.YLabel.String, 'Dim 4 index');
    testCase.verifyEmpty(fig.UserData.ModeDropDown);
end

function testFiveDimensionsAndSingleton(testCase)
    a = reshape(testCase.TestData.A, [4, 6, 8, 1, 3]);
    fig = visualizeMatField(a, 'ExtraIndices', [5, 2], 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    testCase.verifyEqual(fig.UserData.Data, a(:, :, :, 1, 2));
    testCase.verifyEqual(fig.UserData.Options.Subspace.ExtraIndices, [4, 1; 5, 2]);
    testCase.verifyEqual(string(fig.UserData.SubspaceControls.Edits(1).Enable), "off");
    testCase.verifyEqual(string(fig.UserData.SubspaceControls.Edits(2).Enable), "off");
end

function testLeadingSingletonAndNonconsecutiveVolumeLabels(testCase)
    a = reshape(single(1:192), [1, 4, 6, 8]);
    fig = visualizeMatField(a, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    testCase.verifyEqual(fig.UserData.Options.AxesDimensions, [2, 3, 4]);
    testCase.verifyEqual(fig.UserData.Axes.ZLabel.String, 'Dim 4 index');
    mode = fig.UserData.ModeDropDown;
    mode.Value = 'slice';
    mode.ValueChangedFcn(mode, []);
    testCase.verifyEqual(fig.UserData.DimensionDropDown.Items, {'Dim 2', 'Dim 3', 'Dim 4'});
end

function testMatV7AndV73DiscoveryAndSelection(testCase)
    for path = testCase.TestData.Paths
        fig = visualizeMatField(path{1}, 'Visible', 'off');
        cleanup = onCleanup(@() closeViewer(fig));
        selector = fig.UserData.VariableDropDown;
        testCase.verifyTrue(any(strcmp(selector.ItemsData, 'nested.field')));
        info = fig.UserData.Options.AvailableVariableInfo;
        testCase.verifyEqual(info(strcmp({info.Path}, 'nested.field')).Size, size(testCase.TestData.A));
        selector.Value = 'nested.field';
        selector.ValueChangedFcn(selector, []);
        testCase.verifyEqual(fig.UserData.Data, testCase.TestData.A(:, :, :, 1));
        closeViewer(fig);
        clear cleanup
    end
end

function testWorkspaceRefreshRetainsExtraIndex(testCase)
    name = testCase.TestData.BaseName;
    assignin('base', name, testCase.TestData.A);
    fig = visualizeMatField('SourceType', 'workspace', 'WorkspaceVariable', name, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    matfield.Subspace.changeIndex(fig, 4, 2, true);
    assignin('base', name, testCase.TestData.A + single(1000));
    refresh = fig.UserData.WorkspaceRefreshButton;
    refresh.ButtonPushedFcn(refresh, []);
    testCase.verifyEqual(fig.UserData.Options.Subspace.ExtraIndices, [4, 2]);
    testCase.verifyEqual(fig.UserData.Data, testCase.TestData.A(:, :, :, 2) + single(1000));
end

function testModeSwitchAndPlaybackStop(testCase)
    a = testCase.TestData.A;
    fig = visualizeMatField(a, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    matfield.Subspace.changeIndex(fig, 4, 2, true);
    mode = fig.UserData.ModeDropDown;
    mode.Value = 'slice';
    mode.ValueChangedFcn(mode, []);
    testCase.verifyEqual(fig.UserData.Options.Subspace.ExtraIndices, [4, 2]);
    timerHandle = fig.UserData.PlaybackTimer;
    button = fig.UserData.PlayButton;
    button.ButtonPushedFcn(button, []);
    matfield.Subspace.changeIndex(fig, 4, 3, true);
    testCase.verifyEqual(timerHandle.Running, 'off');
    testCase.verifyEqual(fig.UserData.Data, a(:, :, :, 3));
end

function testNonfiniteSubarrayRollsBack(testCase)
    a = testCase.TestData.A;
    a(:, :, :, 2) = NaN;
    fig = visualizeMatField(a, 'PlotType', 'slice', 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    matfield.Subspace.changeIndex(fig, 4, 2, true);
    testCase.verifyEqual(fig.UserData.Data, a(:, :, :, 1));
    testCase.verifyEqual(fig.UserData.SubspaceControls.Edits(1).Value, 1);
    testCase.verifyNotEmpty(fig.UserData.LastSubspaceError);
    matfield.Subspace.changeIndex(fig, 4, 3, true);
    testCase.verifyFalse(isfield(fig.UserData, 'LastSubspaceError'));
end

function testSubspaceLayoutResize(testCase)
    fig = visualizeMatField(testCase.TestData.A, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));
    for width = [1100, 850, 650]
        fig.Position(3) = width;
        matfield.Layout.applyResponsiveViewerLayout(fig, true);
        testCase.verifyTrue(isgraphics(fig.UserData.Layout.Subspace.Panel));
        testCase.verifyEqual(numel(fig.UserData.MainGrid.RowHeight), 3);
        testCase.verifyLessThanOrEqual(fig.UserData.MainGrid.RowHeight{1}, 180);
        testCase.verifyEqual(fig.UserData.Colorbar.Parent, fig.UserData.Layout.PlotCanvas);
    end
end

function closeViewer(fig)
    if isgraphics(fig), close(fig); end
end
