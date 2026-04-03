function [org, channelName] = parse_channel_spec(channel)
%PARSE_CHANNEL_SPEC   Parse a channel string into org and channel name.
%
% Args:
%   channel - Channel string in 'org/channel' format (e.g. 'mip-org/core')
%
% Returns:
%   org         - Organization name (e.g. 'mip-org', 'mylab')
%   channelName - Channel name (e.g. 'core', 'dev', 'custom')
%
% Examples:
%   [org, ch] = parse_channel_spec('mip-org/core')   % -> 'mip-org', 'core'
%   [org, ch] = parse_channel_spec('mip-org/dev')    % -> 'mip-org', 'dev'
%   [org, ch] = parse_channel_spec('mylab/custom')   % -> 'mylab', 'custom'

if nargin < 1 || isempty(channel)
    channel = 'mip-org/core';
end

parts = strsplit(channel, '/');

if length(parts) == 2
    org = parts{1};
    channelName = parts{2};
else
    error('mip:invalidChannel', ...
          'Invalid channel format "%s". Use "org/channel" (e.g. "mip-org/core").', channel);
end

end
