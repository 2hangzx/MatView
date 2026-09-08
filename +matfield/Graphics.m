classdef Graphics
    %GRAPHICS Provide shared graphics, slider, colorbar, and formatting utilities.
    methods (Static)
        function setControlGroupVisible(controls, isVisible)
            visibility = 'off';
            if isVisible
                visibility = 'on';
            end
            for index = 1:numel(controls)
                if isgraphics(controls{index})
                    controls{index}.Visible = visibility;
                end
            end
        end

        function setControlEnabled(control, isEnabled)
            if isempty(control) || ~isgraphics(control)
                return
            end
            enabled = 'off';
            if isEnabled
                enabled = 'on';
            end
            control.Enable = enabled;
        end

        function setVolumeAlphaLayout(alphaText, alphaSlider, isoSelectionMode)
            if isempty(alphaSlider) || ~isgraphics(alphaSlider)
                return
            end
            if strcmp(isoSelectionMode, 'single')
                alphaText.Layout.Column = 11;
                alphaSlider.Layout.Column = [12, 14];
            else
                alphaText.Layout.Column = 7;
                alphaSlider.Layout.Column = [8, 14];
            end
        end

        function configureSliderTicks(slider, axisLength)
            slider.MajorTicks = unique(round(linspace(1, axisLength, min(5, axisLength))));
            slider.MinorTicks = [];
        end

        function configureValueSliderTicks(slider, valueRange)
            ticks = unique(linspace(valueRange(1), valueRange(2), 5));
            slider.MajorTicks = ticks;
            slider.MajorTickLabels = arrayfun(@matfield.Graphics.formatNumber, ticks, 'UniformOutput', false);
            slider.MinorTicks = [];
        end

        function configureCompactValueSliderTicks(slider, valueRange)
            ticks = unique(linspace(valueRange(1), valueRange(2), 3));
            slider.MajorTicks = ticks;
            slider.MajorTickLabels = arrayfun(@matfield.Graphics.formatNumber, ticks, 'UniformOutput', false);
            slider.MinorTicks = [];
        end

        function refreshColorbarPresentation(colorbarHandle)
            if ~matfield.Graphics.hasGraphics(colorbarHandle)
                return
            end
            drawnow limitrate nocallbacks
            ticks = colorbarHandle.Ticks;
            if isempty(ticks)
                return
            end
        
            precision = 7;
            labels = matfield.Graphics.formatTickValues(ticks, precision);
            while numel(unique(labels)) < numel(labels) && precision < 9
                precision = precision + 1;
                labels = matfield.Graphics.formatTickValues(ticks, precision);
            end
            try
                colorbarHandle.Ruler.Exponent = 0;
            catch
                % Older releases can omit the public numeric-ruler handle.
            end
            colorbarHandle.TickLabels = labels;
            colorbarHandle.TickLabelInterpreter = 'none';
            colorbarHandle.FontName = 'Consolas';
            colorbarHandle.FontSize = 11;
        end

        function restoreAutomaticColorbarTicks(colorbarHandle)
            if matfield.Graphics.hasGraphics(colorbarHandle)
                colorbarHandle.TickLabelsMode = 'auto';
            end
        end

        function labels = formatTickValues(values, precision)
            formatSpec = sprintf('%%.%dg', precision);
            labels = arrayfun(@(value) sprintf(formatSpec, value), ...
                values, 'UniformOutput', false);
        end

        function indices = makeSampleIndices(axisLength, maximumLength)
            step = max(1, ceil(axisLength / maximumLength));
            indices = 1:step:axisLength;
            if indices(end) ~= axisLength
                indices(end + 1) = axisLength;
            end
        end

        function limits = makeSafeLimits(limits)
            limits = double(limits(:).');
            if numel(limits) ~= 2 || any(~isfinite(limits)) || limits(1) > limits(2)
                error('visualizeMatField:InvalidLimits', ...
                    'Color limits must be a finite [low high] pair with low <= high.');
            end
            if limits(1) == limits(2)
                padding = max(abs(limits(1)) * 1e-6, 1e-9);
                limits = limits + [-padding, padding];
            end
        end

        function textValue = formatNumber(value)
            if isnan(value)
                textValue = 'NaN';
            elseif isinf(value)
                textValue = char(string(value));
            else
                textValue = sprintf('%.6g', value);
            end
        end

        function tf = hasGraphics(item)
            tf = ~isempty(item) && all(isgraphics(item));
        end

    end
end
