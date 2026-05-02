function [owner, channelName] = parse_channel_spec(channel)
%PARSE_CHANNEL_SPEC   Parse a channel string into owner and channel name.
%
% Args:
%   channel - Channel string in 'owner/channel' format (e.g. 'mip-org/core')
%
% Returns:
%   owner       - GitHub repo owner (user or organization, e.g. 'mip-org', 'mylab')
%   channelName - Channel name (e.g. 'core', 'dev', 'custom')
%
% Examples:
%   [owner, ch] = parse_channel_spec('mip-org/core')   % -> 'mip-org', 'core'
%   [owner, ch] = parse_channel_spec('mip-org/dev')    % -> 'mip-org', 'dev'
%   [owner, ch] = parse_channel_spec('mylab/custom')   % -> 'mylab', 'custom'

if nargin < 1 || isempty(channel)
    channel = 'mip-org/core';
end

parts = strsplit(channel, '/');

if length(parts) == 2
    owner = parts{1};
    channelName = parts{2};
else
    error('mip:invalidChannel', ...
          'Invalid channel format "%s". Use "owner/channel" (e.g. "mip-org/core").', channel);
end

end
