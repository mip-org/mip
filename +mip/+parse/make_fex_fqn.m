function fqn = make_fex_fqn(packageName)
%MAKE_FEX_FQN   Create an FQN for a File Exchange URL install.
%
% Args:
%   packageName - Package name
%
% Returns:
%   fqn - Canonical FQN: 'fex/name'

fqn = ['fex/' packageName];

end
