function fqn = make_mhl_fqn(packageName)
%MAKE_MHL_FQN   Create an FQN for a .mhl install without an explicit channel.
%
% Args:
%   packageName - Package name
%
% Returns:
%   fqn - Canonical FQN: 'mhl/name'

fqn = ['mhl/' packageName];

end
