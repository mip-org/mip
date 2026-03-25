function url = index(channel)
%INDEX   Get the URL for the mip package index.
%
% Usage:
%   url = mip.index()            - Get URL for default channel (core)
%   url = mip.index('dev')       - Get URL for named channel
%
% Channels map to GitHub Pages URLs by convention:
%   'core' -> https://mip-org.github.io/mip-core/index.json
%   'dev'  -> https://mip-org.github.io/mip-dev/index.json

if nargin < 1 || isempty(channel)
    channel = 'core';
end

url = sprintf('https://mip-org.github.io/mip-%s/index.json', channel);

end
