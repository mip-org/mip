function installed = is_installed(fqn)
%IS_INSTALLED   Check if a package is installed.
%
% Args:
%   fqn - FQN (canonical or 3-part shorthand, e.g.
%         'gh/mip-org/core/chebfun', 'mip-org/core/chebfun',
%         'local/mypkg', 'fex/mypkg')
%
% Returns:
%   installed - True if an installed package matches the FQN. Checked
%               via mip.resolve.installed_dir rather than by existence of
%               mip.paths.get_package_dir, which for a repository FQN that
%               is not installed can be a channel directory of the same
%               name.

fqn = mip.parse.canonical_fqn(fqn);
installed = ~isempty(mip.resolve.installed_dir(fqn));

end
