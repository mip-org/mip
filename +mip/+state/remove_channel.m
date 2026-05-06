function remove_channel(channel)
%REMOVE_CHANNEL   Unsubscribe from a channel.
%
% No-op (with a warning) if the channel is not currently subscribed.
%
% Args:
%   channel - Channel spec in 'org/channel' form, or a bare '<name>'
%             which is shorthand for '<name>/<name>'.

    channel = mip.parse.normalize_channel_spec(channel);

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
