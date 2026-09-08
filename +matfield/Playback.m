classdef Playback
    %PLAYBACK Own the shared viewer timer lifecycle and playback controls.
    methods (Static)
        function toggleViewerPlayback(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            playbackTimer = state.PlaybackTimer;
            if isempty(playbackTimer) || ~isvalid(playbackTimer)
                return
            end
            if strcmp(playbackTimer.Running, 'on')
                stop(playbackTimer);
                source.Text = '播放';
            else
                playbackTimer.Period = state.PlaybackIntervalEdit.Value;
                source.Text = '暂停';
                start(playbackTimer);
            end
        end

        function updateViewerPlaybackPeriod(fig, source, ~)
            if ~isvalid(fig)
                return
            end
            state = fig.UserData;
            playbackTimer = state.PlaybackTimer;
            if isempty(playbackTimer) || ~isvalid(playbackTimer)
                return
            end
            wasRunning = strcmp(playbackTimer.Running, 'on');
            if wasRunning
                stop(playbackTimer);
            end
            playbackTimer.Period = source.Value;
            if wasRunning
                start(playbackTimer);
            end
        end

        function pauseViewerPlayback(fig)
            if isempty(fig) || ~isvalid(fig) || isempty(fig.UserData) || ...
                    ~isfield(fig.UserData, 'PlaybackTimer')
                return
            end
            state = fig.UserData;
            playbackTimer = state.PlaybackTimer;
            if ~isempty(playbackTimer) && isvalid(playbackTimer) && ...
                    strcmp(playbackTimer.Running, 'on')
                stop(playbackTimer);
            end
            if isfield(state, 'PlayButton') && ~isempty(state.PlayButton) && ...
                    isgraphics(state.PlayButton)
                if ~strcmp(state.PlayButton.Text, '播放')
                    state.PlayButton.Text = '播放';
                end
            end
        end

        function stopViewerPlayback(fig, deleteTimer)
            if isempty(fig) || ~isvalid(fig) || isempty(fig.UserData) || ...
                    ~isfield(fig.UserData, 'PlaybackTimer')
                return
            end
            matfield.Playback.pauseViewerPlayback(fig);
            playbackTimer = fig.UserData.PlaybackTimer;
            if deleteTimer && ~isempty(playbackTimer) && isvalid(playbackTimer)
                delete(playbackTimer);
            end
        end

        function closeViewerFigure(fig, ~)
            if ~isvalid(fig)
                return
            end
            matfield.Playback.stopViewerPlayback(fig, true);
            delete(fig);
        end

    end
end
