function remove_channel(channel)
%REMOVE_CHANNEL   Unsubscribe from a channel.
%
% No-op (with a warning) if the channel is not currently subscribed.
%
% Args:
%   channel - Channel spec in 'org/channel' form, or a bare '<name>'
%             which is shorthand for '<name>/<name>'.

    channel = normalizeChannel(channel);

    channels = mip.state.get_channels();
    mask = strcmpi(channels, channel);
    if ~any(mask)
        fprintf('Channel "%s" is not subscribed.\n', channel);
        return
    end
    channels(mask) = [];
    mip.state.set_channels(channels);

    fprintf('Unsubscribed from channel "%s".\n', channel);
end


function channel = normalizeChannel(channel)
    if isstring(channel)
        channel = char(channel);
    end
    if ~ischar(channel) || isempty(channel)
        error('mip:invalidChannel', 'Channel must be a non-empty string.');
    end
    if ~contains(channel, '/')
        channel = [channel '/' channel];
    end
    parts = strsplit(channel, '/');
    if length(parts) ~= 2 || any(cellfun('isempty', parts))
        error('mip:invalidChannel', ...
              'Invalid channel format "%s". Use "org/channel".', channel);
    end
end
