function root = baseline_root()
%BASELINE_ROOT   The root the session uses when no environment is active.
%
% Usage:
%   root = mip.env.baseline_root()
%
% The baseline root is the value of MIP_ROOT at session start if it was
% set externally, otherwise the root derived from mip's own install
% location. Activation never moves the baseline: while an environment is
% active this returns the saved pre-activation root, so named-env
% operations (which anchor to <baseline root>/envs/) resolve against the
% same store regardless of which environment is active.

s = mip.env.active();
if isempty(s)
    root = mip.paths.root();
    return
end

root = s.saved_mip_root;
if isempty(root)
    root = mip.paths.default_root();
    return
end

% Validate the saved external root the same way mip.paths.root validates
% MIP_ROOT.
if ~mip.paths.is_root(root)
    error('mip:rootInvalid', ...
        ['The baseline root ''%s'' (the MIP_ROOT value saved at ' ...
         'activation) does not exist or does not contain a ' ...
         '''packages'' subdirectory.'], root);
end

end
