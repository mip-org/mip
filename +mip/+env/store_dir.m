function d = store_dir()
%STORE_DIR   The named-environment store: <baseline root>/envs.
%
% Usage:
%   d = mip.env.store_dir()
%
% Named environments live in this directory, one subdirectory per env.
% The store is anchored to the baseline root (not the active root), so
% named-env operations resolve the same way while an environment is
% active, and an externally set MIP_ROOT keeps its named envs inside
% that root.

d = fullfile(mip.env.baseline_root(), 'envs');

end
