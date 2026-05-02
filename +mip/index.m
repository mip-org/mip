function url = index(channel)
%INDEX   Get the URL for the mip package index.
%
% Usage:
%   mip index                           - Get URL for default channel (mip-org/core)
%   mip index --channel owner/channel   - Get URL for a user-hosted channel
%   mip index --channel <name>          - Shorthand for --channel <name>/<name>
%
% Channel URL mapping:
%   'mip-org/core'   -> https://mip-org.github.io/mip-core/index.json
%   'owner/channel'  -> https://owner.github.io/mip-channel/index.json
%   '<name>'         -> https://<name>.github.io/mip-<name>/index.json

if nargin < 1 || isempty(channel)
    channel = 'mip-org/core';
end

[org, channelName] = mip.parse.parse_channel_spec(channel);

url = sprintf('https://%s.github.io/mip-%s/index.json', org, channelName);

end
