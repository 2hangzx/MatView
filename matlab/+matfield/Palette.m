classdef Palette
    %PALETTE Shared colormap controls and recoloring without rebuilding geometry.
    methods (Static)
        function names = names()
            candidates = {'turbo', 'jet', 'hot', 'parula', 'gray', 'bone', ...
                'copper', 'pink', 'cool', 'spring', 'summer', 'autumn', ...
                'winter', 'hsv', 'sky', 'abyss', 'lines', 'colorcube', 'prism', 'flag', 'white'};
            names = candidates(cellfun(@(name) exist(name, 'file') ~= 0 || ...
                exist(name, 'builtin') ~= 0, candidates));
        end

        function [name, map] = resolve(name)
            name = strtrim(char(string(name)));
            names = matfield.Palette.names();
            known = find(strcmpi(names, name), 1);
            if ~isempty(known)
                name = names{known};
            end
            try
                if ~isvarname(name), error('Invalid colormap name'); end
                map = feval(name, 256);
            catch
                error('visualizeMatField:InvalidColormap', ...
                    'Unknown colormap "%s". Use a colormap name such as turbo, jet or hot.', name);
            end
            if ~isnumeric(map) || ~isreal(map) || ~ismatrix(map) || size(map, 2) ~= 3 || ...
                    size(map, 1) < 2 || ~all(isfinite(map), 'all') || any(map < 0 | map > 1, 'all')
                error('visualizeMatField:InvalidColormap', ...
                    'Colormap "%s" must return an N-by-3 RGB array in [0,1].', name);
            end
            map = double(map);
        end

        function [body, layout] = createControls(panel, opts, hasTarget)
            layout = struct('Height', 0, 'DropDown', gobjects(0));
            body = panel;
            if opts.Specified.Colormap
                return
            end
            outer = uigridlayout(panel, [2, 1]);
            outer.RowHeight = {40, '1x'};
            outer.Padding = [0, 0, 0, 0];
            outer.RowSpacing = 0;
            header = uigridlayout(outer, [1, 2]);
            header.Layout.Row = 1;
            header.ColumnWidth = {80, '1x'};
            header.RowHeight = {30};
            header.Padding = [10, 4, 10, 6];
            uilabel(header, 'Text', '色图');
            names = matfield.Palette.names();
            if ~any(strcmp(names, opts.Colormap))
                names{end + 1} = opts.Colormap;
            end
            dropdown = uidropdown(header, 'Items', names, 'Value', opts.Colormap);
            dropdown.Enable = matfield.Subspace.onOff(hasTarget);
            dropdown.Tooltip = '切片、等值面与颜色栏同步换色；不改变数值范围、索引和视角。';
            body = uipanel(outer, 'BorderType', 'none');
            body.Layout.Row = 2;
            layout = struct('Height', 40, 'DropDown', dropdown);
        end

        function wire(fig, layout)
            state = fig.UserData;
            state.ColormapDropDown = layout.DropDown;
            fig.UserData = state;
            if matfield.Graphics.hasGraphics(layout.DropDown)
                layout.DropDown.ValueChangedFcn = @(src, ~) matfield.Palette.change(fig, src.Value);
            end
        end

        function change(fig, requestedName)
            if ~isvalid(fig), return; end
            state = fig.UserData;
            if isempty(state.Variable) || state.Options.Specified.Colormap, return; end
            previous = state.Options.Colormap;
            try
                [name, map] = matfield.Palette.resolve(requestedName);
                colormap(state.Axes, map);
                if strcmp(state.PlotMode, 'volume')
                    % Existing patches use fixed RGB faces. Store each level when
                    % it is built and recolor those same patches, never recontour.
                    for patch = state.Patches(:).'
                        if ~isgraphics(patch), continue; end
                        level = getappdata(patch, 'MatfieldIsoValue');
                        t = (level - state.ColorLimits(1)) / diff(state.ColorLimits);
                        index = 1 + round(max(0, min(1, t)) * (size(map, 1) - 1));
                        patch.FaceColor = map(index, :);
                    end
                end
                state.Options.Colormap = name;
                state.ColormapDropDown.Value = name;
                fig.UserData = state;
                matfield.Graphics.synchronizeColorbar(fig);
                drawnow limitrate nocallbacks
            catch exception
                state.ColormapDropDown.Value = previous;
                matfield.Viewer.showViewerAlert(fig, exception.message, '无法切换色图');
            end
        end
    end
end
