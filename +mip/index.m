function url = index(channel)
%INDEX   Get the URL for the mip package index.
%
% Usage:
%   url = mip.index()                       - Get URL for default channel (mip-org/core)
%   url = mip.index('mip-org/core')         - Get URL for mip-org/core
%   url = mip.index('owner/channel')        - Get URL for a user-hosted channel
%
% Channel URL mapping:
%   'mip-org/core'   -> https://mip-org.github.io/mip-core/index.json
%   'mip-org/dev'    -> https://mip-org.github.io/mip-dev/index.json
%   'owner/channel'  -> https://owner.github.io/mip-channel/index.json

if nargin < 1 || isempty(channel)
    channel = 'mip-org/core';
end

[org, channelName] = mip.utils.parse_channel_spec(channel);

url = sprintf('https://%s.github.io/mip-%s/index.json', org, channelName);

end
