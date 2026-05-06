function append_channel(channel)
%APPEND_CHANNEL   Subscribe to a channel at the bottom of the priority list.
%
% If the channel is already subscribed, it is moved to the bottom of the
% priority list. Bare-name installs without `--channel` consult
% mip-org/core first, then subscribed channels in priority order.
%
% Args:
%   channel - Channel spec in '<owner>/<channel>' form, or a bare
%             '<owner>' which is shorthand for '<owner>/<owner>'.

    channel = mip.parse.normalize_channel_spec(channel);

    if strcmp(channel, 'mip-org/core')
        fprintf('mip-org/core is the default channel and is always consulted first.\n');
        return
    end

    channels = mip.state.get_channels();
    channels(strcmp(channels, channel)) = [];
    channels = [channels, {channel}];
    mip.state.set_channels(channels);

    fprintf('Subscribed to channel "%s" (lowest priority).\n', channel);
end
