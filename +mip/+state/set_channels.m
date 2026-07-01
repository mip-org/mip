function set_channels(channels)
%SET_CHANNELS   Set the subscribed channel list (atomic write).
%
% Args:
%   channels - Cell array of channel specs in priority order (highest
%              priority first). Each entry must be in '<owner>/<channel>'
%              form; callers are responsible for normalizing shorthand
%              inputs.
%
% Persisted in stack-like order: the highest-priority (most recently
% added) channel is written last, matching MIP_LOADED_PACKAGES semantics.
% Callers pass priority order (highest first), so the list is reversed
% before writing. get_channels reverses it back on read.

    channelsFile = fullfile(mip.paths.get_packages_dir(), 'channels.txt');
    mip.state.write_line_list(channelsFile, flip(channels));
end
