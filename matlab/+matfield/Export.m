classdef Export
    %EXPORT Isolated plot-only renderers and atomic, finite playback exports.
    methods (Static)
        function wire(fig)
            menu = uimenu(fig, 'Text', '导出', 'Tag', 'MatfieldExport');
            uimenu(menu, 'Text', '导出图片…', 'Tag', 'MatfieldExportImage', ...
                'MenuSelectedFcn', @(~, ~) matfield.Export.dialog(fig, 'image'));
            uimenu(menu, 'Text', '导出播放动画（GIF / MP4）…', 'Tag', 'MatfieldExportAnimation', ...
                'MenuSelectedFcn', @(~, ~) matfield.Export.dialog(fig, 'animation'));
            uimenu(menu, 'Text', '导出当前切片数据…', 'Tag', 'MatfieldExportData', ...
                'MenuSelectedFcn', @(~, ~) matfield.Export.dialog(fig, 'data'));
            matfield.Export.updateMenu(fig);
        end

        function updateMenu(fig)
            if ~isgraphics(fig), return; end
            state = fig.UserData;
            ready = isstruct(state) && isfield(state, 'Data') && ~isempty(state.Data);
            busy = isappdata(fig, 'MatfieldExporting') && getappdata(fig, 'MatfieldExporting');
            tags = {'Image', 'Animation', 'Data'};
            enabled = [ready, ready && matfield.Export.canAnimate(state), ...
                ready && strcmp(state.PlotMode, 'slice')];
            for k = 1:3
                item = findall(fig, 'Tag', ['MatfieldExport', tags{k}]);
                if ~isempty(item)
                    item.Enable = matlab.lang.OnOffSwitchState(enabled(k) && ~busy);
                end
            end
        end

        function tf = canAnimate(state)
            tf = isfield(state, 'FieldDimension') && state.FieldDimension == 3 && ...
                (strcmp(state.PlotMode, 'slice') || ...
                strcmp(state.IsoSelectionMode, 'single') || isscalar(state.IsoValues));
        end

        function [count, rate] = defaults(state)
            count = 101;
            if strcmp(state.PlotMode, 'slice')
                count = state.DataSize(state.Dimension);
            end
            rate = 1 / 0.12;
            if isfield(state, 'PlaybackIntervalEdit') && matfield.Graphics.hasGraphics(state.PlaybackIntervalEdit)
                rate = 1 / state.PlaybackIntervalEdit.Value;
            end
            rate = min(60, max(0.1, rate));
        end

        function write(fig, outputFile, varargin)
            if ~isgraphics(fig) || ~isstruct(fig.UserData) || ...
                    ~isfield(fig.UserData, 'Data') || isempty(fig.UserData.Data)
                error('visualizeMatField:ExportNotReady', '请先选择目标变量并完成绘图。');
            end
            if isappdata(fig, 'MatfieldExporting') && getappdata(fig, 'MatfieldExporting')
                error('visualizeMatField:ExportBusy', '已有导出任务正在进行。');
            end
            parser = inputParser;
            addParameter(parser, 'Width', 1600, @(v) matfield.Export.validInteger(v, 320, 8192));
            addParameter(parser, 'Height', 1200, @(v) matfield.Export.validInteger(v, 240, 8192));
            addParameter(parser, 'Frames', [], @(v) isempty(v) || matfield.Export.validInteger(v, 1, 10000));
            addParameter(parser, 'FrameRate', [], @(v) isempty(v) || ...
                (isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0.1 && v <= 60));
            addParameter(parser, 'Progress', [], @(v) isempty(v) || isa(v, 'function_handle'));
            choices = matfield.Export.componentChoices();
            addParameter(parser, 'Components', choices(:, 1));
            parse(parser, varargin{:});
            opts = parser.Results;
            if opts.Width * opts.Height > 32e6
                error('visualizeMatField:InvalidExportSize', '导出图片不能超过 3200 万像素。');
            end
            outputFile = char(string(outputFile));
            [folder, ~, ext] = fileparts(outputFile);
            ext = lower(ext);
            if isempty(folder), folder = pwd; end
            if ~isfolder(folder)
                error('visualizeMatField:InvalidExportPath', '输出目录不存在：%s', folder);
            end
            isAnimation = any(strcmp(ext, {'.gif', '.mp4', '.avi'}));
            isData = any(strcmp(ext, {'.mat', '.csv'}));
            if ~isAnimation && ~isData && ~any(strcmp(ext, {'.png', '.jpg', '.jpeg', '.tif', '.tiff'}))
                error('visualizeMatField:InvalidExportType', '请选择 PNG/JPG/TIFF、GIF/MP4/AVI 或 MAT/CSV。');
            end
            state = fig.UserData;
            if isAnimation && ~matfield.Export.canAnimate(state)
                error('visualizeMatField:AnimationUnavailable', '动画导出需要三维数组的 Slice 或指定单层等值面模式。');
            end
            if isData && ~strcmp(state.PlotMode, 'slice')
                error('visualizeMatField:SliceExportOnly', '只有 Slice 模式可以导出当前切片数据。');
            end
            if strcmp(ext, '.mp4') && (mod(opts.Width, 2) || mod(opts.Height, 2))
                error('visualizeMatField:InvalidExportSize', 'MP4 的宽和高必须为偶数像素。');
            end
            timerWasRunning = isfield(state, 'PlaybackTimer') && ~isempty(state.PlaybackTimer) && ...
                isvalid(state.PlaybackTimer) && strcmp(state.PlaybackTimer.Running, 'on');
            matfield.Playback.pauseViewerPlayback(fig);
            setappdata(fig, 'MatfieldExporting', true);
            cleanupViewer = onCleanup(@() matfield.Export.restoreViewer(fig, timerWasRunning));
            matfield.Export.updateMenu(fig);
            tempFolder = tempname(folder);
            mkdir(tempFolder);
            cleanupFiles = onCleanup(@() rmdir(tempFolder, 's'));
            temporary = fullfile(tempFolder, ['output', ext]);
            if isData
                [data, metadata] = matfield.Export.slicePayload(state);
                if strcmp(ext, '.mat')
                    save(temporary, 'data', 'metadata');
                else
                    if isinteger(data)
                        writematrix(data, temporary);
                    else
                        % fprintf retains full float64 precision, including NaN/Inf.
                        file = fopen(temporary, 'w');
                        if file < 0, error('visualizeMatField:ExportIO', '无法写入 CSV。'); end
                        cleanupCSV = onCleanup(@() fclose(file));
                        format = [repmat('%.17g,', 1, size(data, 2) - 1), '%.17g\n'];
                        fprintf(file, format, data.');
                        clear cleanupCSV
                    end
                    sidecar = [temporary, '.json'];
                    file = fopen(sidecar, 'w', 'n', 'UTF-8');
                    if file < 0, error('visualizeMatField:ExportIO', '无法写入元信息。'); end
                    cleanupJSON = onCleanup(@() fclose(file));
                    fprintf(file, '%s', jsonencode(metadata, 'PrettyPrint', true));
                    clear cleanupJSON
                    movefile(sidecar, [outputFile, '.json'], 'f');
                end
            else
                [renderFig, ax, cb] = matfield.Export.createRenderer(state, opts);
                cleanupRenderer = onCleanup(@() delete(renderFig));
                if isAnimation
                    matfield.Export.animation(state, renderFig, ax, cb, temporary, opts);
                else
                    matfield.Export.saveFrame(renderFig, temporary, opts);
                end
            end
            movefile(temporary, outputFile, 'f');
        end

        function tf = validInteger(v, low, high)
            tf = isnumeric(v) && isscalar(v) && isreal(v) && isfinite(v) && ...
                v == fix(v) && v >= low && v <= high;
        end

        function choices = componentChoices()
            choices = {
                'axes',           '坐标轴 / 坐标框', '';
                'axis_labels',    '坐标轴标签',       'axes';
                'axis_ticks',     '坐标轴刻度与数字', 'axes';
                'title',          '标题',             '';
                'colorbar',       '颜色栏',           '';
                'colorbar_label', '颜色栏标签',       'colorbar';
                'colorbar_ticks', '颜色栏刻度与数字', 'colorbar';
            };
        end

        function parts = resolveComponents(opts)
            choices = matfield.Export.componentChoices();
            if ~isfield(opts, 'Components')
                parts = string(choices(:, 1));
                return
            end
            value = opts.Components;
            if ~(isempty(value) || ischar(value) || isstring(value) || iscellstr(value))
                error('visualizeMatField:InvalidExportComponents', 'Components 必须是部件名称列表。');
            end
            parts = string(value);
            parts = parts(:);
            if any(~ismember(parts, choices(:, 1)))
                error('visualizeMatField:InvalidExportComponents', 'Components 包含未知的导出部件。');
            end
            selected = ismember(choices(:, 1), parts);
            enabled = strcmp(choices(:, 3), '') | ismember(choices(:, 3), parts);
            parts = string(choices(selected & enabled, 1));
        end

        function restoreViewer(fig, wasRunning)
            if ~isgraphics(fig), return; end
            setappdata(fig, 'MatfieldExporting', false);
            matfield.Export.updateMenu(fig);
            if wasRunning
                state = fig.UserData;
                if isvalid(state.PlaybackTimer)
                    state.PlayButton.Text = '暂停';
                    start(state.PlaybackTimer);
                end
            end
        end

        function [data, metadata] = slicePayload(state)
            if state.FieldDimension == 2
                data = state.Data;
                dimensions = matfield.Subspace.axisDimensions(state.Options);
                sliceDimension = [];
                sliceIndex = [];
            else
                selection = {':', ':', ':'};
                selection{state.Dimension} = state.Index;
                dims = setdiff(1:3, state.Dimension, 'stable');
                data = reshape(state.Data(selection{:}), state.DataSize(dims));
                dimensions = matfield.Subspace.axisDimensions(state.Options);
                sliceDimension = dimensions(state.Dimension);
                sliceIndex = state.Index;
                dimensions = dimensions(dims);
            end
            metadata = struct('Variable', state.Variable, 'DataType', class(data), ...
                'IndexBase', 1, 'SliceDimension', sliceDimension, 'SliceIndex', sliceIndex, ...
                'DataDimensions', dimensions, 'ColorLimits', state.Axes.CLim, ...
                'Colormap', state.Options.Colormap, 'DataOrder', ...
                'source array order; first dimension is horizontal in the viewer', ...
                'SourceType', state.Source.Type);
            if isfield(state.Options, 'Subspace')
                selection = state.Options.Subspace;
                metadata.OriginalSize = selection.OriginalSize;
                metadata.RetainedDimensions = selection.RetainedDimensions;
                metadata.ExtraIndices = selection.ExtraIndices;
            else
                metadata.OriginalSize = size(state.Data);
                metadata.RetainedDimensions = matfield.Subspace.axisDimensions(state.Options);
                metadata.ExtraIndices = [];
            end
        end

        function [renderFig, ax, cb] = createRenderer(state, opts)
            parts = matfield.Export.resolveComponents(opts);
            renderFig = figure('Visible', 'off', 'Color', 'white', 'Units', 'pixels', ...
                'Position', [50, 50, max(480, 750 * opts.Width / opts.Height), 750], ...
                'MenuBar', 'none', 'ToolBar', 'none');
            try
                ax = copyobj(state.Axes, renderFig);
                ax.Toolbar.Visible = 'off';
                ax.ContextMenu = [];
                colormap(ax, colormap(state.Axes));
                ax.Visible = matlab.lang.OnOffSwitchState(ismember("axes", parts));
                set([ax.XLabel, ax.YLabel, ax.ZLabel], 'Visible', ...
                    matlab.lang.OnOffSwitchState(ismember("axis_labels", parts)));
                if ~ismember("axis_ticks", parts)
                    ax.TickLength = [0, 0];
                    ax.XTickLabel = {};
                    ax.YTickLabel = {};
                    ax.ZTickLabel = {};
                    ax.XAxis.Exponent = 0;
                    ax.YAxis.Exponent = 0;
                    ax.ZAxis.Exponent = 0;
                end
                ax.Title.Visible = matlab.lang.OnOffSwitchState(ismember("title", parts));
                cb = gobjects(0);
                if ismember("colorbar", parts)
                    sourceBar = state.Colorbar;
                    cb = colorbar(ax, 'manual');
                    cb.FontName = sourceBar.FontName;
                    cb.FontSize = sourceBar.FontSize;
                    cb.Ruler.Exponent = 0;
                    if ismember("colorbar_ticks", parts)
                        cb.Ticks = sourceBar.Ticks;
                        cb.TickLabels = sourceBar.TickLabels;
                        cb.TickLabelInterpreter = sourceBar.TickLabelInterpreter;
                    else
                        cb.Ticks = [];
                    end
                    if ismember("colorbar_label", parts)
                        cb.Label.String = sourceBar.Label.String;
                        cb.Label.Interpreter = sourceBar.Label.Interpreter;
                        cb.Label.FontSize = sourceBar.Label.FontSize;
                    end
                end
                matfield.Export.placeColorbar(ax, cb);
                drawnow nocallbacks
                if strcmp(state.PlotMode, 'volume')
                    navigation = matfield.VolumeView.captureAxesNavigation(state.Axes);
                    matfield.VolumeView.restoreAxesNavigation(ax, navigation);
                    ax.CameraPositionMode = 'manual';
                    ax.CameraTargetMode = 'manual';
                    ax.CameraUpVectorMode = 'manual';
                    ax.CameraViewAngleMode = 'manual';
                end
            catch exception
                delete(renderFig);
                rethrow(exception)
            end
        end

        function placeColorbar(ax, cb)
            % Position excludes the tick text and the label. Reserve room for both.
            sizePixels = ax.Parent.Position(3:4);
            gutter = 16;
            if ~isempty(cb)
                gutter = 54 + 16 * double(~isempty(cb.Label.String));
                if ~isempty(cb.Ticks)
                    labels = string(cb.TickLabels);
                    longest = max([0; strlength(labels(:))]);
                    gutter = max(140, 64 + ceil(double(longest) * cb.FontSize * 0.9));
                end
                cb.Units = 'pixels';
                cb.Position = [sizePixels(1) - gutter + 18, 36, 18, sizePixels(2) - 72];
            end
            ax.Units = 'pixels';
            ax.PositionConstraint = 'outerposition';
            ax.OuterPosition = [16, 28, sizePixels(1) - gutter - 16, sizePixels(2) - 58];
        end

        function saveFrame(renderFig, path, opts)
            exportgraphics(renderFig, path, 'Units', 'pixels', ...
                'Width', opts.Width, 'Height', opts.Height, 'Resolution', 120, ...
                'Padding', 'figure', 'PreserveAspectRatio', 'on', 'BackgroundColor', 'white');
            % Some renderer/DPI combinations round the requested size by a pixel.
            % Normalize only the outer white padding, without scaling plot pixels.
            rgb = imread(path);
            actual = size(rgb, [1, 2]);
            target = [opts.Height, opts.Width];
            if ~isequal(actual, target)
                if any(abs(actual - target) > 2)
                    error('visualizeMatField:ExportSizeMismatch', '图像渲染尺寸与请求尺寸不符。');
                end
                normalized = repmat(cast(255, 'like', rgb), [target, size(rgb, 3)]);
                height = min(actual(1), target(1));
                width = min(actual(2), target(2));
                normalized(1:height, 1:width, :) = rgb(1:height, 1:width, :);
                imwrite(normalized, path);
            end
        end

        function animation(state, renderFig, ax, cb, path, opts)
            [defaultCount, defaultRate] = matfield.Export.defaults(state);
            if isempty(opts.Frames), opts.Frames = defaultCount; end
            if isempty(opts.FrameRate), opts.FrameRate = defaultRate; end
            [folder, ~, ext] = fileparts(path);
            png = fullfile(folder, 'frame.png');
            writer = [];
            if ~strcmp(ext, '.gif')
                profile = 'MPEG-4';
                if strcmp(ext, '.avi'), profile = 'Motion JPEG AVI'; end
                writer = VideoWriter(path, profile);
                writer.FrameRate = opts.FrameRate;
                open(writer);
                cleanupVideo = onCleanup(@() close(writer));
            end
            for k = 1:opts.Frames
                matfield.Export.progress(opts, k - 1);
                if k > 1
                    state = matfield.Export.advanceState(state);
                    matfield.Export.updateFrame(state, ax, cb);
                end
                matfield.Export.saveFrame(renderFig, png, opts);
                rgb = imread(png);
                if strcmp(ext, '.gif')
                    [indexed, map] = rgb2ind(rgb, 256);
                    if k == 1
                        imwrite(indexed, map, path, 'gif', 'LoopCount', Inf, 'DelayTime', 1 / opts.FrameRate);
                    else
                        imwrite(indexed, map, path, 'gif', 'WriteMode', 'append', 'DelayTime', 1 / opts.FrameRate);
                    end
                else
                    writeVideo(writer, rgb);
                end
            end
            matfield.Export.progress(opts, opts.Frames);
        end

        function progress(opts, done)
            if ~isempty(opts.Progress) && ~opts.Progress(done, opts.Frames)
                error('visualizeMatField:ExportCancelled', '导出已取消，目标文件未改动。');
            end
        end

        function state = advanceState(state)
            if strcmp(state.PlotMode, 'slice')
                state.Index = mod(state.Index, state.DataSize(state.Dimension)) + 1;
            else
                if ~strcmp(state.IsoSelectionMode, 'single')
                    state.ExactIsoValue = state.IsoValues(1);
                    state.IsoSelectionMode = 'single';
                end
                next = state.ExactIsoValue + diff(state.GlobalRange) / 100;
                if next > state.GlobalRange(2), next = state.GlobalRange(1); end
                state.ExactIsoValue = next;
            end
        end

        function updateFrame(state, ax, cb)
            if strcmp(state.PlotMode, 'slice')
                [data, ~] = matfield.Export.slicePayload(state);
                image = findobj(ax, 'Type', 'image');
                image.CData = data.';
                if strcmp(state.ColorMode, 'slice')
                    previousLimits = ax.CLim;
                    finite = data(isfinite(data));
                    if isempty(finite)
                        ax.CLim = state.GlobalClim;
                    else
                        ax.CLim = matfield.Graphics.makeSafeLimits([min(finite), max(finite)]);
                    end
                    if ~isempty(cb) && ~isempty(cb.Ticks) && ~isequal(ax.CLim, previousLimits)
                        cb.Ticks = linspace(ax.CLim(1), ax.CLim(2), numel(cb.Ticks));
                        matfield.Graphics.refreshColorbarPresentation(cb);
                        matfield.Export.placeColorbar(ax, cb);
                    end
                end
                if strcmp(ax.Title.Visible, 'on')
                    dimensions = matfield.Subspace.axisDimensions(state.Options);
                    title(ax, sprintf('%s | Dim %d = %d', state.Variable, ...
                        dimensions(state.Dimension), state.Index), 'Interpreter', 'none');
                end
            else
                delete(findobj(ax, 'Type', 'patch'));
                delete(findobj(ax, 'Type', 'light'));
                indices = state.SampleIndices;
                sampled = state.Data(indices{1}, indices{2}, indices{3});
                sampled(~isfinite(sampled)) = NaN;
                [c1, c2, c3] = meshgrid(indices{1}, indices{2}, indices{3});
                matfield.VolumeView.drawIsosurfaces(ax, c1, c2, c3, ...
                    permute(sampled, [2, 1, 3]), state.ExactIsoValue, state.ColorLimits, state.SurfaceAlpha);
                camlight(ax, 'headlight');
                lighting(ax, 'gouraud');
                if strcmp(ax.Title.Visible, 'on')
                    title(ax, sprintf('%s | isosurface = %.9g', state.Variable, state.ExactIsoValue), ...
                        'Interpreter', 'none');
                end
            end
            drawnow nocallbacks
        end

        function dialog(fig, kind)
            state = fig.UserData;
            wasRunning = isfield(state, 'PlaybackTimer') && ~isempty(state.PlaybackTimer) && ...
                isvalid(state.PlaybackTimer) && strcmp(state.PlaybackTimer.Running, 'on');
            matfield.Playback.pauseViewerPlayback(fig);
            cleanupPlayback = onCleanup(@() matfield.Export.restoreViewer(fig, wasRunning));
            settings = {};
            if ~strcmp(kind, 'data')
                settings = matfield.Export.settingsDialog(fig, kind, state);
                if isempty(settings), return; end
            end
            switch kind
                case 'image', filters = {'*.png', 'PNG'; '*.jpg', 'JPEG'; '*.tif', 'TIFF'};
                case 'animation', filters = {'*.gif', 'GIF 动画'; '*.mp4', 'MP4 视频'; '*.avi', 'AVI 视频'};
                otherwise, filters = {'*.mat', 'MAT 数据与元信息'; '*.csv', 'CSV + JSON 元信息'};
            end
            [name, folder] = uiputfile(filters, '选择导出文件');
            if isequal(name, 0), return; end
            progress = uiprogressdlg(fig, 'Title', '正在导出', 'Message', '正在准备画面…', ...
                'Cancelable', matlab.lang.OnOffSwitchState(strcmp(kind, 'animation')));
            cleanupProgress = onCleanup(@() close(progress));
            settings = [settings, {'Progress', @(done, total) matfield.Export.dialogProgress(progress, done, total)}];
            try
                matfield.Export.write(fig, fullfile(folder, name), settings{:});
            catch exception
                if ~strcmp(exception.identifier, 'visualizeMatField:ExportCancelled')
                    matfield.Viewer.showViewerAlert(fig, exception.message, '无法导出');
                end
            end
        end

        function settings = settingsDialog(fig, kind, state)
            fields = {'Width', '宽度 / px', 1600, [320, 8192], 'on'; ...
                      'Height', '高度 / px', 1200, [240, 8192], 'on'};
            if strcmp(kind, 'animation')
                [count, rate] = matfield.Export.defaults(state);
                fields = [fields; {'Frames', '帧数', min(count, 10000), [1, 10000], 'on'; ...
                                   'FrameRate', '帧率 / fps', rate, [0.1, 60], 'off'}];
            end
            choices = matfield.Export.componentChoices();
            rows = size(fields, 1) + size(choices, 1) + 3;
            height = 34 * rows + 20;
            origin = fig.Position(1:2) + (fig.Position(3:4) - [380, height]) / 2;
            dlg = uifigure('Name', '导出设置', 'WindowStyle', 'modal', ...
                'Position', [origin, 380, height], 'CloseRequestFcn', @(src, ~) uiresume(src), ...
                'UserData', false);
            cleanup = onCleanup(@() delete(dlg));
            grid = uigridlayout(dlg, [rows, 3]);
            grid.ColumnWidth = {22, '1x', '1x'};
            grid.RowHeight = repmat({28}, 1, rows);
            grid.RowSpacing = 6;
            edits = gobjects(size(fields, 1), 1);
            for row = 1:size(fields, 1)
                label = uilabel(grid, 'Text', fields{row, 2});
                label.Layout.Row = row;
                label.Layout.Column = [1, 2];
                edits(row) = uieditfield(grid, 'numeric', 'Value', fields{row, 3}, ...
                    'Limits', fields{row, 4}, 'RoundFractionalValues', fields{row, 5});
                edits(row).Layout.Row = row;
                edits(row).Layout.Column = 3;
            end
            header = uilabel(grid, 'Text', '导出部件', 'FontWeight', 'bold');
            header.Layout.Row = size(fields, 1) + 1;
            header.Layout.Column = [1, 3];
            body = uicheckbox(grid, 'Text', '图像主体（必选）', 'Value', true, 'Enable', 'off');
            body.Layout.Row = size(fields, 1) + 2;
            body.Layout.Column = [1, 3];
            checks = gobjects(size(choices, 1), 1);
            for k = 1:size(choices, 1)
                checks(k) = uicheckbox(grid, 'Text', choices{k, 2}, 'Value', true);
                checks(k).Layout.Row = size(fields, 1) + 2 + k;
                checks(k).Layout.Column = [1 + double(~isempty(choices{k, 3})), 3];
            end
            for k = 1:size(choices, 1)
                children = checks(strcmp(choices(:, 3), choices{k, 1}));
                if ~isempty(children)
                    checks(k).ValueChangedFcn = @(src, ~) set(children, 'Enable', ...
                        matlab.lang.OnOffSwitchState(src.Value));
                end
            end
            cancel = uibutton(grid, 'Text', '取消', 'ButtonPushedFcn', @(~, ~) uiresume(dlg));
            cancel.Layout.Row = rows;
            cancel.Layout.Column = 2;
            accept = uibutton(grid, 'Text', '确定', 'ButtonPushedFcn', @confirm);
            accept.Layout.Row = rows;
            accept.Layout.Column = 3;
            settings = {};
            uiwait(dlg);
            if isvalid(dlg) && dlg.UserData
                for k = 1:size(fields, 1)
                    settings(end + 1:end + 2) = {fields{k, 1}, edits(k).Value};
                end
                selected = arrayfun(@(check) check.Value, checks);
                settings(end + 1:end + 2) = {'Components', choices(selected, 1)};
            end

            function confirm(~, ~)
                dlg.UserData = true;
                uiresume(dlg);
            end
        end

        function proceed = dialogProgress(progress, done, total)
            progress.Value = done / total;
            progress.Message = sprintf('已生成 %d / %d 帧', done, total);
            drawnow
            proceed = ~progress.CancelRequested;
        end
    end
end
