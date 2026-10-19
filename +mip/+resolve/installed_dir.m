function name = installed_dir(fqn)
%INSTALLED_DIR   Find the on-disk directory name for an installed package.
%
% Scans the parent directory of the package (determined by its FQN's
% source-type layout) for an entry whose name matches the FQN's last
% component under the equivalence rules of mip.name.match (case-
% insensitive, dash/underscore-equivalent).
%
% The returned name is the actual directory name on disk, preserving its
% case and separators. Callers use this form as the canonical package
% name for subsequent storage and comparison, so that plain strcmp/
% ismember against already-stored FQNs keeps working.
%
% For a repository package (gh/<owner>/<repo>) only directories that are
% repository packages (mip.paths.is_repo_package_dir) match, so a channel
% directory of the same name is never mistaken for the package. Conversely,
% a channel FQN never matches inside a repository package's directory.
%
% Args:
%   fqn - Canonical FQN (gh/<owner>/<channel>/<name>, gh/<owner>/<repo>,
%         local/<name>, fex/<name>, ...)
%
% Returns:
%   name - char row vector with the on-disk name, or '' if no matching
%          directory exists.

name = '';

r = mip.parse.parse_package_arg(fqn);
if ~r.is_fqn
    return
end

packagesDir = mip.paths.get_packages_dir();
if r.is_repo
    parentDir = fullfile(packagesDir, 'gh', r.owner);
elseif strcmp(r.type, 'gh')
    parentDir = fullfile(packagesDir, 'gh', r.owner, r.channel);
    if mip.paths.is_repo_package_dir(parentDir)
        return
    end
else
    parentDir = fullfile(packagesDir, r.type);
end

if ~exist(parentDir, 'dir')
    return
end

entries = dir(parentDir);
for i = 1:length(entries)
    if ~entries(i).isdir || startsWith(entries(i).name, '.')
        continue
    end
    if mip.name.match(entries(i).name, r.name)
        if r.is_repo && ~mip.paths.is_repo_package_dir(fullfile(parentDir, entries(i).name))
            continue
        end
        name = entries(i).name;
        return
    end
end

end
