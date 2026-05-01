function url = index(channel)
%INDEX   Get the URL for the mip package index.
%
% Usage:
%   mip index                       - Display URL for default channel (mip-org/core)
%   mip index --channel mip-org/core   - Display URL for mip-org/core
%   mip index --channel owner/channel  - Display URL for a user-hosted channel
%
% Channel URL mapping:
%   'mip-org/core'   -> https://mip-org.github.io/mip-core/index.json
%   'mip-org/dev'    -> https://mip-org.github.io/mip-dev/index.json
%   'owner/channel'  -> https://owner.github.io/mip-channel/index.json

if nargin < 1 || isempty(channel)
    channel = 'mip-org/core';
end

[org, channelName] = mip.parse.parse_channel_spec(channel);

url = sprintf('https://%s.github.io/mip-%s/index.json', org, channelName);

end
