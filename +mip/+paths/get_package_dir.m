function pkgDir = get_package_dir(org, channelName, packageName)
%GET_PACKAGE_DIR   Get the directory path for a namespaced package.
%
% Performs a case- and dash/underscore-insensitive lookup. If a matching
% directory exists on disk, returns its actual path (preserving the
% on-disk casing/separators). If no matching directory exists, falls back
% to a path constructed from packageName as-given — this supports callers
% that need a path before the package is installed (e.g. install).
%
% Args:
%   org         - Organization name (e.g. 'mip-org')
%   channelName - Channel name (e.g. 'core')
%   packageName - Package name (e.g. 'chebfun')
%
% Returns:
%   pkgDir - Full path: <root>/packages/<org>/<channel>/<actual-name>/

packagesDir = mip.paths.get_packages_dir();
onDisk = mip.resolve.installed_dir(org, channelName, packageName);
if ~isempty(onDisk)
    pkgDir = fullfile(packagesDir, org, channelName, onDisk);
else
    pkgDir = fullfile(packagesDir, org, channelName, packageName);
end

end
