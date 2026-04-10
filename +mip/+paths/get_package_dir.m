function pkgDir = get_package_dir(org, channelName, packageName)
%GET_PACKAGE_DIR   Get the directory path for a namespaced package.
%
% Args:
%   org         - Organization name (e.g. 'mip-org')
%   channelName - Channel name (e.g. 'core')
%   packageName - Package name (e.g. 'chebfun')
%
% Returns:
%   pkgDir - Full path: <root>/packages/<org>/<channel>/<package>/

packagesDir = mip.paths.get_packages_dir();
pkgDir = fullfile(packagesDir, org, channelName, packageName);

end
