function d = store_dir()
%STORE_DIR   Directory holding the named environments: <baseline root>/envs.
%
% Usage:
%   d = mip.env.store_dir()
%
% Anchored to the baseline root (the session's no-environment root), so
% named-environment operations resolve against the same store even while
% some other environment is active, and MIP_ROOT-isolated sessions keep
% their named environments inside that root.

d = fullfile(mip.paths.baseline_root(), 'envs');

end
