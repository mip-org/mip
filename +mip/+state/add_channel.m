function add_channel(channel)
%ADD_CHANNEL   Subscribe to a channel (or move it to highest priority).
%
% If the channel is already subscribed, it is moved to the top of the
% priority list. Bare-name installs without `--channel` consult
% mip-org/core first, then subscribed channels in priority order.
%
% Args:
%   channel - Channel spec in '<owner>/<channel>' form, or a bare
%             '<owner>' which is shorthand for '<owner>/<owner>'.

    channel = mip.parse.normalize_channel_spec(channel);

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
