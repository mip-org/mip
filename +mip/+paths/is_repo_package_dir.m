function tf = is_repo_package_dir(d)
%IS_REPO_PACKAGE_DIR   True if a directory under packages/gh/<owner>/ is a repository package.
%
% Under <root>/packages/gh/<owner>/, a directory that contains mip.json is
% a package published from its own repository (FQN 'gh/<owner>/<repo>');
% any other directory is a channel whose subdirectories are packages.
%
% Args:
%   d - Absolute path of a directory directly under packages/gh/<owner>/
%
% Returns:
%   tf - Logical

tf = isfile(fullfile(d, 'mip.json'));

end
