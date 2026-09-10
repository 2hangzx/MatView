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
    suffix = erase(char(java.util.UUID.randomUUID), '-');
    testCase.TestData.WorkspaceName = ['vmfTestField', suffix(1:10)];
end


function teardownOnce(testCase)
    if isfile(testCase.TestData.MatFile)
        delete(testCase.TestData.MatFile);
    end
    clearBaseVariable(testCase.TestData.WorkspaceName);
end


function testEmptyFileSelectionState(testCase)
    fig = visualizeMatField('Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEmpty(fig.UserData.MatFile);
    testCase.verifyEqual(fig.UserData.Variable, '');
    testCase.verifyEqual(string(fig.UserData.VariableDropDown.Enable), "off");
    testCase.verifyEqual(string(fig.UserData.Axes.Visible), "off");
end


function testTrueZeroArgumentCall(testCase)
    fig = visualizeMatField();
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEqual(fig.UserData.Source.Type, 'matfile');
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


function testDirectLocalArrayUsesMemorySnapshot(testCase)
    localVolume = reshape(single(1:120), [4, 5, 6]);
    fig = visualizeMatField(localVolume, 'PlotType', 'volume', ...
        'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEqual(fig.UserData.Source.Type, 'memory');
    testCase.verifyEqual(fig.UserData.Source.RootName, 'localVolume');
    testCase.verifyEqual(fig.UserData.Variable, 'localVolume');
    testCase.verifyEqual(class(fig.UserData.Data), 'single');

    localVolume(:) = 0;
    testCase.verifyEqual(max(localVolume, [], 'all'), single(0));
    testCase.verifyGreaterThan(max(fig.UserData.Data, [], 'all'), single(0));
end


function testDirectTwoDimensionalArrayUsesSlice(testCase)
    localMatrix = reshape(single(1:20), [4, 5]);
    fig = visualizeMatField(localMatrix, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    testCase.verifyEqual(fig.UserData.Source.Type, 'memory');
    testCase.verifyEqual(fig.UserData.FieldDimension, 2);
    testCase.verifyEqual(fig.UserData.PlotMode, 'slice');
    testCase.verifyEmpty(fig.UserData.Dimension);
end


function testDirectNestedStructureOffersTargetSelector(testCase)
    localStruct = struct( ...
        'nested', struct('volume', reshape(single(1:120), [4, 5, 6])), ...
        'matrix', reshape(1:20, [4, 5]), ...
        'ignoredVector', 1:8);
    fig = visualizeMatField(localStruct, 'Visible', 'off');
    cleanup = onCleanup(@() closeViewer(fig));

    expectedPath = 'localStruct.nested.volume';
    testCase.verifyTrue(any(strcmp( ...
        fig.UserData.Options.AvailableVariables, expectedPath)));
    testCase.verifyFalse(any(contains( ...
        fig.UserData.Options.AvailableVariables, 'ignoredVector')));
    selector = fig.UserData.VariableDropDown;
    selector.Value = expectedPath;
    selector.ValueChangedFcn(selector, []);
    testCase.verifyEqual(fig.UserData.Variable, expectedPath);
    testCase.verifyEqual(fig.UserData.PlotMode, 'volume');
end


function testBaseWorkspaceExplicitTargetAndRefresh(testCase)
    workspaceName = testCase.TestData.WorkspaceName;
    clearBaseVariable(workspaceName);
    baseCleanup = onCleanup(@() clearBaseVariable(workspaceName));
    assignin('base', workspaceName, reshape(single(1:120), [4, 5, 6]));

    fig = visualizeMatField('SourceType', 'workspace', ...
        'WorkspaceVariable', workspaceName, 'Visible', 'off');
    figureCleanup = onCleanup(@() closeViewer(fig));
    testCase.verifyEqual(fig.UserData.Source.Type, 'workspace');
    testCase.verifyEqual(fig.UserData.PlotMode, 'volume');
    testCase.verifyTrue(isgraphics(fig.UserData.WorkspaceRefreshButton));

    assignin('base', workspaceName, reshape(single(1:20), [4, 5]));
    refreshButton = fig.UserData.WorkspaceRefreshButton;
    refreshButton.ButtonPushedFcn(refreshButton, []);
    testCase.verifyEqual(fig.UserData.PlotMode, 'slice');
    testCase.verifyEqual(fig.UserData.DataSize, [4, 5]);

    clearBaseVariable(workspaceName);
    refreshButton = fig.UserData.WorkspaceRefreshButton;
    refreshButton.ButtonPushedFcn(refreshButton, []);
    testCase.verifyEmpty(fig.UserData.Variable);
    testCase.verifyEqual(string(fig.UserData.Axes.Visible), "off");
    clear figureCleanup baseCleanup
end


function testBaseWorkspaceNestedStructureDiscovery(testCase)
    workspaceName = [testCase.TestData.WorkspaceName, 'Nested'];
    clearBaseVariable(workspaceName);
    baseCleanup = onCleanup(@() clearBaseVariable(workspaceName));
    workspaceStruct = struct('caseA', struct( ...
        'field', reshape(single(1:120), [4, 5, 6]), ...
        'ignored', 1:8));
    assignin('base', workspaceName, workspaceStruct);

    fig = visualizeMatField('SourceType', 'workspace', 'Visible', 'off');
    figureCleanup = onCleanup(@() closeViewer(fig));
    expectedPath = [workspaceName, '.caseA.field'];
    testCase.verifyTrue(any(strcmp( ...
        fig.UserData.Options.AvailableVariables, expectedPath)));
    targetSelector = fig.UserData.VariableDropDown;
    targetSelector.Value = expectedPath;
    targetSelector.ValueChangedFcn(targetSelector, []);
    testCase.verifyEqual(fig.UserData.Variable, expectedPath);
    testCase.verifyEqual(fig.UserData.PlotMode, 'volume');
    clear figureCleanup baseCleanup
end


function testSourceTypeDropDownSwitchesToWorkspace(testCase)
    workspaceName = testCase.TestData.WorkspaceName;
    clearBaseVariable(workspaceName);
    baseCleanup = onCleanup(@() clearBaseVariable(workspaceName));
    assignin('base', workspaceName, reshape(single(1:120), [4, 5, 6]));

    fig = visualizeMatField('Visible', 'off');
    figureCleanup = onCleanup(@() closeViewer(fig));
    sourceSelector = fig.UserData.SourceTypeDropDown;
    sourceSelector.Value = 'workspace';
    sourceSelector.ValueChangedFcn(sourceSelector, []);

    testCase.verifyEqual(fig.UserData.Source.Type, 'workspace');
    testCase.verifyTrue(any(strcmp( ...
        fig.UserData.Options.AvailableVariables, workspaceName)));
    testCase.verifyTrue(isgraphics(fig.UserData.WorkspaceRefreshButton));
    clear figureCleanup baseCleanup
end


function testMemorySourceCannotBeBrowsedWithoutValue(testCase)
    testCase.verifyError( ...
        @() visualizeMatField('SourceType', 'memory', 'Visible', 'off'), ...
        'visualizeMatField:MemorySourceRequiresValue');
end


function testSourceRoundTripStopsPlayback(testCase)
    workspaceName = testCase.TestData.WorkspaceName;
    clearBaseVariable(workspaceName);
    baseCleanup = onCleanup(@() clearBaseVariable(workspaceName));
    assignin('base', workspaceName, reshape(single(1:120), [4, 5, 6]));

    fig = visualizeMatField('PlotType', 'slice', 'Dimension', 3, ...
        'Visible', 'off');
    figureCleanup = onCleanup(@() closeViewer(fig));
    pathEdit = fig.UserData.FilePathEdit;
    pathEdit.Value = testCase.TestData.MatFile;
    pathEdit.ValueChangedFcn(pathEdit, []);
    targetSelector = fig.UserData.VariableDropDown;
    targetSelector.Value = 'volume3d';
    targetSelector.ValueChangedFcn(targetSelector, []);

    playbackTimer = fig.UserData.PlaybackTimer;
    playButton = fig.UserData.PlayButton;
    playButton.ButtonPushedFcn(playButton, []);
    testCase.verifyEqual(playbackTimer.Running, 'on');

    sourceSelector = fig.UserData.SourceTypeDropDown;
    sourceSelector.Value = 'workspace';
    sourceSelector.ValueChangedFcn(sourceSelector, []);
    testCase.verifyFalse(isvalid(playbackTimer));
    testCase.verifyEqual(fig.UserData.Source.Type, 'workspace');

    sourceSelector = fig.UserData.SourceTypeDropDown;
    sourceSelector.Value = 'matfile';
    sourceSelector.ValueChangedFcn(sourceSelector, []);
    testCase.verifyEqual(fig.UserData.Source.Type, 'matfile');
    testCase.verifyTrue(isgraphics(fig.UserData.FilePathEdit));
    testCase.verifyEqual(string(fig.UserData.VariableDropDown.Enable), "off");
    clear figureCleanup baseCleanup
end


function closeViewer(fig)
    if isgraphics(fig)
        close(fig);
    end
end


function clearBaseVariable(variableName)
    if evalin('base', sprintf('exist(''%s'', ''var'')', variableName))
        evalin('base', ['clear ', variableName]);
    end
end
