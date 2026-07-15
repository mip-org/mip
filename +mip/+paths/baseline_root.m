function root = baseline_root()
%BASELINE_ROOT   Get the session's no-environment root directory.
%
% Usage:
%   root = mip.paths.baseline_root()
%
% The baseline root is the root mip uses when no environment is active:
% mip.paths.root() itself when nothing is activated, otherwise the root
% that was in effect when the active environment was activated (an
% externally set MIP_ROOT, or the root derived from mip's own install
% location). The named-environment store (<baseline root>/envs/) is
% anchored here, so "mip env" operations resolve against the same store
% no matter which environment is active.

env = mip.state.get_active_env();
if isempty(env)
    root = mip.paths.root();
    return
end

root = env.saved.mip_root;
if isempty(root)
    root = mip.paths.derived_root();
end
if isempty(root)
    error('mip:rootNotFound', ...
          'Could not determine the baseline mip root directory.');
end

end
