function pkgDir = get_package_dir(fqn)
%GET_PACKAGE_DIR   Get the directory path for a namespaced package.
%
% Performs a case- and dash/underscore-insensitive lookup on the last
% FQN component. If a matching directory exists on disk, returns its
% actual path (preserving the on-disk casing/separators). If no matching
% directory exists, falls back to a path constructed from the FQN name
% as-given — this supports callers that need a path before the package
% is installed (e.g. install).
%
% Args:
%   fqn - Canonical FQN:
%           'gh/<org>/<channel>/<name>'  (GitHub channel package)
%           'local/<name>'               (local directory install)
%           'fex/<name>'                 (File Exchange / --url install)
%           'web/<name>'                 (generic remote .zip --url install)
%           'mhl/<name>'                 (.mhl install with no --channel)
%
% Returns:
%   pkgDir - Full path:
%             <root>/packages/gh/<org>/<channel>/<name>/   (gh)
%             <root>/packages/<type>/<name>/               (non-gh)

packagesDir = mip.paths.get_packages_dir();
r = mip.parse.parse_package_arg(fqn);

if ~r.is_fqn
    error('mip:invalidFqn', ...
          'get_package_dir requires a fully qualified name; got "%s".', fqn);
end

onDisk = mip.resolve.installed_dir(fqn);
if isempty(onDisk)
    onDisk = r.name;
end

if strcmp(r.type, 'gh')
    pkgDir = fullfile(packagesDir, 'gh', r.org, r.channel, onDisk);
else
    pkgDir = fullfile(packagesDir, r.type, onDisk);
end

end
