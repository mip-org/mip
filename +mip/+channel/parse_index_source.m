function [kind, owner, name] = parse_index_source(source)
%PARSE_INDEX_SOURCE   Split an index source string into its parts.
%
% An index source is where a package index is published. It is either a
% channel, written '<owner>/<channel>' (index on GitHub Pages), or a
% repository that publishes its own package, written
% 'github.com/<owner>/<repo>' (index attached to the repository's
% 'mip-index' release). See mip.channel.index_source for building one
% from an FQN.
%
% Args:
%   source - Index source string. Empty means the default channel
%            'mip-org/core'.
%
% Returns:
%   kind  - 'channel' or 'repo'
%   owner - GitHub owner
%   name  - Channel name (kind 'channel') or repository name (kind 'repo')

if nargin < 1 || isempty(source)
    source = 'mip-org/core';
end

if startsWith(source, 'github.com/')
    parts = strsplit(source(length('github.com/')+1:end), '/');
    if length(parts) ~= 2 || any(cellfun('isempty', parts))
        error('mip:invalidChannel', ...
              'Invalid repository index source "%s".', source);
    end
    kind = 'repo';
    owner = parts{1};
    name = parts{2};
else
    kind = 'channel';
    [owner, name] = mip.parse.parse_channel_spec(source);
end

end
