function cleanup_package_parents(fqn)
%CLEANUP_PACKAGE_PARENTS   Remove empty parent dirs above a removed package.
%
% For a gh FQN this walks up through <channel>, <owner>, and the 'gh'
% root; for a non-gh FQN it only needs to check the source-type directory.
%
% Args:
%   fqn - Canonical FQN of the removed package

packagesDir = mip.paths.get_packages_dir();
r = mip.parse.parse_package_arg(fqn);
if strcmp(r.type, 'gh')
    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh', r.owner, r.channel));
    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh', r.owner));
    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh'));
else
    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, r.type));
end

end
