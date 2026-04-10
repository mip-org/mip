function fqn = make_fqn(org, channelName, packageName)
%MAKE_FQN   Create a fully qualified package name.
%
% Args:
%   org         - Organization name (e.g. 'mip-org')
%   channelName - Channel name (e.g. 'core')
%   packageName - Package name (e.g. 'chebfun')
%
% Returns:
%   fqn - Fully qualified name: 'org/channel/package'

fqn = [org '/' channelName '/' packageName];

end
