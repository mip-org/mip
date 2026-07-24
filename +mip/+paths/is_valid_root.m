function tf = is_valid_root(candidate)
%IS_VALID_ROOT   Check whether a directory is a valid mip root.
%
% Usage:
%   tf = mip.paths.is_valid_root(candidate)
%
% A directory is a mip root exactly when it exists and contains a
% 'packages' subdirectory. This is the same signal mip.paths.root uses to
% validate MIP_ROOT, and it is also what marks a directory as an
% environment (an environment is just a root): there is no separate
% marker file.
%
% Args:
%   candidate - Directory path to check.
%
% Returns:
%   tf - logical scalar

tf = isfolder(candidate) && isfolder(fullfile(candidate, 'packages'));

end
