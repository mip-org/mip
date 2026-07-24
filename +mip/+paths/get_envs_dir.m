function d = get_envs_dir()
%GET_ENVS_DIR   The named-environment store: <base root>/envs.
%
% Usage:
%   d = mip.paths.get_envs_dir()
%
% Named environments live in this directory, one subdirectory per env.
% The store is anchored to the base root (not the active root), so
% named-env operations resolve the same way while an environment is
% active, and an externally set MIP_ROOT keeps its named envs inside
% that root.

d = fullfile(mip.paths.root('base'), 'envs');

end
