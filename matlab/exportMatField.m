function outputFile = exportMatField(fig, outputFile, varargin)
%EXPORTMATFIELD Export the current plot, playback sequence, or raw slice.
%   exportMatField(fig, 'plot.png', 'Width', 1600, 'Height', 1200)
%   exportMatField(fig, 'plot.png', 'Components', {'axes', 'axis_ticks'})
%   exportMatField(fig, 'play.gif', 'Frames', 60, 'FrameRate', 10)
%   exportMatField(fig, 'play.mp4', 'Frames', 60, 'FrameRate', 10)
%   exportMatField(fig, 'slice.mat')  % data + metadata, original array order
%   exportMatField(fig, 'slice.csv')  % numeric data + .csv.json metadata
%   Images include axes, title and colorbar, with no controls. Animation starts
%   at the current slice/single-isovalue and wraps using the playback step.
%   Width/Height are pixels. Export never advances the viewer itself.
    matfield.Export.write(fig, outputFile, varargin{:});
end
