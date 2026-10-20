function fqn = make_fqn(owner, channelName, packageName)
%MAKE_FQN   Create a fully qualified GitHub package name.
%
% GitHub packages live under the 'gh/' source-type prefix on disk and in
% canonical FQNs. A channel package has a 4-part FQN; a package published
% from its own repository has a 3-part FQN, and is requested here by
% passing an empty channelName.
%
% Args:
%   owner       - GitHub owner (user or organization, e.g. 'mip-org')
%   channelName - Channel name (e.g. 'core'), or '' for a repository package
%   packageName - Package name (e.g. 'chebfun'). For a repository package
%                 this is also the repository name.
%
% Returns:
%   fqn - Canonical FQN: 'gh/<owner>/<channel>/<name>', or
%         'gh/<owner>/<name>' when channelName is empty.

if isempty(channelName)
    fqn = ['gh/' owner '/' packageName];
else
    fqn = ['gh/' owner '/' channelName '/' packageName];
end

end
