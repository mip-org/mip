function assert_no_repo_channel_overlap(fqn)
%ASSERT_NO_REPO_CHANNEL_OVERLAP   Reject installs where a channel and a repository package would share a directory.
%
% A channel '<channel>' of owner '<owner>' is installed under
% packages/gh/<owner>/<channel>/, and a repository package
% gh/<owner>/<repo> under packages/gh/<owner>/<repo>/. An owner with both
% a channel 'foo' (repository mip-foo) and a package repository 'foo'
% would map both to the same directory. Installing a repository package
% over an existing channel directory, or a channel package into an
% installed repository package's directory, fails with
% 'mip:repo:conflictsWithChannel'. Names are compared case-insensitively,
% since the two may collide on a case-insensitive file system.
%
% Args:
%   fqn - Canonical FQN about to be installed. Non-gh FQNs are ignored.

r = mip.parse.parse_package_arg(fqn);
if ~strcmp(r.type, 'gh')
    return
end

ownerDir = fullfile(mip.paths.get_packages_dir(), 'gh', r.owner);
if ~isfolder(ownerDir)
    return
end

if r.is_repo
    target = r.name;
else
    target = r.channel;
end

entries = dir(ownerDir);
for i = 1:length(entries)
    if ~entries(i).isdir || startsWith(entries(i).name, '.') || ...
            ~strcmpi(entries(i).name, target)
        continue
    end
    isRepoDir = mip.paths.is_repo_package_dir(fullfile(ownerDir, entries(i).name));
    if r.is_repo && ~isRepoDir
        error('mip:repo:conflictsWithChannel', ...
              ['Cannot install "%s": the channel %s/%s is installed in the ' ...
               'same directory (%s). Uninstall the packages of that channel first.'], ...
              mip.parse.display_fqn(fqn), r.owner, entries(i).name, ...
              fullfile(ownerDir, entries(i).name));
    elseif ~r.is_repo && isRepoDir
        error('mip:repo:conflictsWithChannel', ...
              ['Cannot install "%s": the repository package %s is installed in ' ...
               'the same directory (%s). Uninstall it first.'], ...
              mip.parse.display_fqn(fqn), ...
              mip.parse.display_fqn(mip.parse.make_fqn(r.owner, '', entries(i).name)), ...
              fullfile(ownerDir, entries(i).name));
    end
end

end
