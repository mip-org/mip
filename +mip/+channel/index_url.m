function url = index_url(source)
%INDEX_URL   Build the URL for a package index.
%
% Usage:
%   url = mip.channel.index_url()                             - URL for default channel (mip-org/core)
%   url = mip.channel.index_url('<owner>/<channel>')          - URL for a user-hosted channel
%   url = mip.channel.index_url('github.com/<owner>/<repo>')  - URL for a repository package
%
% URL mapping:
%   'mip-org/core'              -> https://mip-org.github.io/mip-core/index.json
%   '<owner>/<channel>'         -> https://<owner>.github.io/mip-<channel>/index.json
%   'github.com/<owner>/<repo>' -> https://github.com/<owner>/<repo>/releases/download/mip-index/index.json

if nargin < 1 || isempty(source)
    source = 'mip-org/core';
end

[kind, owner, name] = mip.channel.parse_index_source(source);

if strcmp(kind, 'repo')
    url = sprintf('https://github.com/%s/%s/releases/download/mip-index/index.json', owner, name);
else
    url = sprintf('https://%s.github.io/mip-%s/index.json', owner, name);
end

end
