function channels = get_channels()
%GET_CHANNELS   Get the list of subscribed channels in priority order.
%
% Returns:
%   channels - Cell array of channel specs (e.g. 'mylab/custom') in
%              priority order (highest priority first). Does NOT include
%              the implicit default 'mip-org/core' channel; that channel
%              is always consulted before any subscribed channel and
%              need not be listed.
%
% Channels are persisted at <root>/packages/channels.txt, one channel
% per line, in stack-like order: the most recently added channel is at
% the END of the file (matching the append semantics of
% MIP_LOADED_PACKAGES). The returned cell array reverses that so the
% highest-priority channel is at index 1.
%
% An existing-but-unreadable channels file raises an error rather than
% returning {}: silently dropping the list would let a subsequent
% set_channels overwrite the file and lose the user's prior subscriptions.

    channelsFile = fullfile(mip.paths.get_packages_dir(), 'channels.txt');
    channels = flip(mip.state.read_line_list(channelsFile, 'error'));
end
