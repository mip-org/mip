function fqn = make_web_fqn(packageName)
%MAKE_WEB_FQN   Create an FQN for a generic remote .zip install.
%
% Args:
%   packageName - Package name
%
% Returns:
%   fqn - Canonical FQN: 'web/name'

fqn = ['web/' packageName];

end
