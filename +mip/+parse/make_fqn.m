function fqn = make_fqn(owner, channelName, packageName)
%MAKE_FQN   Create a fully qualified GitHub-channel package name.
%
% GitHub-hosted channel packages live under the 'gh/' source-type
% prefix on disk and in canonical FQNs.
%
% Args:
%   owner       - GitHub repo owner (user or organization, e.g. 'mip-org')
%   channelName - Channel name (e.g. 'core')
%   packageName - Package name (e.g. 'chebfun')
%
% Returns:
%   fqn - Canonical FQN: 'gh/owner/channel/name'

fqn = ['gh/' owner '/' channelName '/' packageName];

end
