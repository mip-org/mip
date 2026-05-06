function add_channel(channel)
%ADD_CHANNEL   Subscribe to a channel (or move it to highest priority).
%
% If the channel is already subscribed, it is moved to the top of the
% priority list. Bare-name installs without `--channel` consult
% mip-org/core first, then subscribed channels in priority order.
%
% Args:
%   channel - Channel spec in 'org/channel' form, or a bare '<name>'
%             which is shorthand for '<name>/<name>'.

    channel = normalizeChannel(channel);

    if strcmpi(channel, 'mip-org/core')
        fprintf('mip-org/core is the default channel and is always consulted first.\n');
        return
    end

    channels = mip.state.get_channels();
    channels(strcmpi(channels, channel)) = [];
    channels = [{channel}, channels];
    mip.state.set_channels(channels);

    fprintf('Subscribed to channel "%s".\n', channel);
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
