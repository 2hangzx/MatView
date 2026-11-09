function tests = testExport
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    testCase.TestData.Folder = tempname;
    mkdir(testCase.TestData.Folder);
end

function teardownOnce(testCase)
    rmdir(testCase.TestData.Folder, 's');
end

function testBlankAnd2DMenu(testCase)
    fig = visualizeMatField('Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    testCase.verifyEqual(string(findall(fig, 'Tag', 'MatfieldExportImage').Enable), "off");
    testCase.verifyError(@() exportMatField(fig, 'empty.png'), 'visualizeMatField:ExportNotReady');
    clear cleanup
    fig = visualizeMatField(single(reshape(1:30, 5, 6)), 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    testCase.verifyEqual(string(findall(fig, 'Tag', 'MatfieldExportAnimation').Enable), "off");
    testCase.verifyEqual(string(findall(fig, 'Tag', 'MatfieldExportData').Enable), "on");
end

function testSliceDataOrderAndMetadata(testCase)
    a = reshape(single(1:420), [5, 6, 7, 2]);
    fig = visualizeMatField(a, 'PlotType', 'slice', 'Dimension', 2, 'Index', 3, ...
        'ExtraIndices', [4, 2], 'Colormap', 'hot', 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    output = fullfile(testCase.TestData.Folder, 'slice.mat');
    exportMatField(fig, output);
    saved = load(output);
    testCase.verifyEqual(saved.data, reshape(a(:, 3, :, 2), 5, 7));
    testCase.verifyClass(saved.data, 'single');
    testCase.verifyEqual(saved.metadata.DataDimensions, [1, 3]);
    testCase.verifyEqual(saved.metadata.SliceDimension, 2);
    testCase.verifyEqual(saved.metadata.SliceIndex, 3);
    testCase.verifyEqual(saved.metadata.ExtraIndices, [4, 2]);
    output = fullfile(testCase.TestData.Folder, 'slice.csv');
    exportMatField(fig, output);
    testCase.verifyEqual(readmatrix(output), double(saved.data));
    testCase.verifyTrue(isfile([output, '.json']));
end

function testImageAndGifFramesDoNotAdvanceUI(testCase)
    fig = visualizeMatField(reshape(single(1:144), [6, 8, 3]), ...
        'PlotType', 'slice', 'Dimension', 3, 'Index', 3, 'ColorLimits', 'slice', 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    original = fig.UserData.Image.CData;
    output = fullfile(testCase.TestData.Folder, 'image.png');
    exportMatField(fig, output, 'Width', 640, 'Height', 480);
    image = imread(output);
    testCase.verifyEqual(size(image, [1, 2]), [480, 640]);
    output = fullfile(testCase.TestData.Folder, 'play.gif');
    exportMatField(fig, output, 'Width', 400, 'Height', 300, 'Frames', 4, 'FrameRate', 5, ...
        'Components', {'title'});
    info = imfinfo(output);
    testCase.verifyEqual(numel(info), 4);
    testCase.verifyEqual(info(1).DelayTime, 20);
    testCase.verifyEqual(fig.UserData.Index, 3);
    testCase.verifyEqual(fig.UserData.Image.CData, original);
end

function testExportComponentsRespectParentsAndPreserveImage(testCase)
    fig = visualizeMatField(peaks(20), 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    state = fig.UserData;
    opts = struct('Width', 640, 'Height', 480);
    opts.Components = {'axis_labels', 'axis_ticks', 'title', 'colorbar_label', 'colorbar_ticks'};
    [renderFig, ax, cb] = matfield.Export.createRenderer(state, opts);
    cleanupRenderer = onCleanup(@() delete(renderFig));
    testCase.verifyEqual(string(ax.Visible), "off");
    testCase.verifyEqual(string(ax.Title.Visible), "on");
    testCase.verifyEqual(string(ax.XLabel.Visible), "off");
    testCase.verifyEmpty(cb);
    output = fullfile(testCase.TestData.Folder, 'components.png');
    matfield.Export.saveFrame(renderFig, output, opts);
    rgb = double(imread(output));
    testCase.verifyTrue(any(max(rgb, [], 3) - min(rgb, [], 3) > 30, 'all'));
    clear cleanupRenderer

    opts.Components = {'axes', 'axis_labels', 'colorbar', 'colorbar_ticks'};
    [renderFig, ax, cb] = matfield.Export.createRenderer(state, opts);
    cleanupRenderer = onCleanup(@() delete(renderFig));
    testCase.verifyEqual(string(ax.Visible), "on");
    testCase.verifyEqual(string(ax.XLabel.Visible), "on");
    testCase.verifyEqual(ax.TickLength, [0, 0]);
    testCase.verifyEqual(string(ax.Title.Visible), "off");
    testCase.verifyEqual(cb.Ticks, state.Colorbar.Ticks);
    testCase.verifyEmpty(cb.Label.String);
    testCase.verifyEqual(string(state.Axes.Title.Visible), "on");
end

function testExportColorbarKeepsViewerTicksAndLabel(testCase)
    data = reshape(linspace(1.000037, 1.000277, 120), [5, 6, 4]);
    fig = visualizeMatField(data, 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    state = fig.UserData;
    % Put the middle of the scale between ticks so only the Value label is
    % expected in the middle of the right-hand text area of the exported PNG.
    sourceBar = state.Colorbar;
    sourceBar.Ticks = linspace(state.Axes.CLim(1), state.Axes.CLim(2), 4);
    matfield.Graphics.refreshColorbarPresentation(sourceBar);
    opts = struct('Width', 640, 'Height', 480);
    [renderFig, ~, bar] = matfield.Export.createRenderer(state, opts);
    cleanupRenderer = onCleanup(@() delete(renderFig));
    testCase.verifyEqual(bar.Ticks, sourceBar.Ticks);
    testCase.verifyEqual(bar.TickLabels, sourceBar.TickLabels);
    testCase.verifyEqual(bar.Label.String, 'Value');
    output = fullfile(testCase.TestData.Folder, 'colorbar.png');
    matfield.Export.saveFrame(renderFig, output, opts);
    rgb = imread(output);
    firstTextColumn = ceil((bar.Position(1) + bar.Position(3)) * opts.Width / renderFig.Position(3)) + 4;
    labelRegion = rgb(216:264, firstTextColumn:end, :);
    testCase.verifyTrue(any(all(labelRegion < 128, 3), 'all'), ...
        'The Value label must be visible in the exported image.');
end

function testVolumeImageSingleAnimationAndMP4(testCase)
    [a, b, c] = ndgrid(linspace(-1, 1, 13), linspace(-1, 1, 15), linspace(-1, 1, 17));
    fig = visualizeMatField(single(a.^2 + b.^2 + c.^2), 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    testCase.verifyError(@() exportMatField(fig, fullfile(testCase.TestData.Folder, 'auto.gif')), ...
        'visualizeMatField:AnimationUnavailable');
    exportMatField(fig, fullfile(testCase.TestData.Folder, 'volume.png'), 'Width', 640, 'Height', 480);
    mode = fig.UserData.IsoModeDropDown;
    mode.Value = 'single';
    mode.ValueChangedFcn(mode, []);
    camera = fig.UserData.Axes.CameraPosition;
    exact = fig.UserData.ExactIsoValue;
    output = fullfile(testCase.TestData.Folder, 'single.gif');
    exportMatField(fig, output, 'Width', 400, 'Height', 300, 'Frames', 3, 'FrameRate', 5);
    testCase.verifyEqual(numel(imfinfo(output)), 3);
    output = fullfile(testCase.TestData.Folder, 'single.mp4');
    exportMatField(fig, output, 'Width', 400, 'Height', 300, 'Frames', 2, 'FrameRate', 5);
    video = VideoReader(output);
    testCase.verifyEqual([video.Width, video.Height], [400, 300]);
    testCase.verifyEqual(round(video.Duration * video.FrameRate), 2);
    testCase.verifyEqual(fig.UserData.Axes.CameraPosition, camera);
    testCase.verifyEqual(fig.UserData.ExactIsoValue, exact);
end

function testCancelKeepsFileAndRestoresViewer(testCase)
    fig = visualizeMatField(reshape(1:120, [5, 6, 4]), 'PlotType', 'slice', 'Visible', 'off');
    cleanup = onCleanup(@() close(fig));
    output = fullfile(testCase.TestData.Folder, 'keep.gif');
    file = fopen(output, 'w'); fprintf(file, 'original'); fclose(file);
    testCase.verifyError(@() exportMatField(fig, output, 'Frames', 5, 'Width', 400, 'Height', 300, ...
        'Progress', @(done, total) done < 1), 'visualizeMatField:ExportCancelled');
    testCase.verifyEqual(fileread(output), 'original');
    testCase.verifyFalse(getappdata(fig, 'MatfieldExporting'));
    testCase.verifyEqual(string(findall(fig, 'Tag', 'MatfieldExportImage').Enable), "on");
end
