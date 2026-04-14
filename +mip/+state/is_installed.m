function installed = is_installed(fqn)
%IS_INSTALLED   Check if a package is installed.
%
% Args:
%   fqn - Fully qualified package name (org/channel/name)
%
% Returns:
%   installed - True if the package directory exists

result = mip.parse.parse_package_arg(fqn);
packageDir = mip.paths.get_package_dir(result.org, result.channel, result.name);
installed = exist(packageDir, 'dir') ~= 0;

end
