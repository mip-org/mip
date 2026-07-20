function s = active()
%ACTIVE   Get the active environment's session state, or [] if none.
%
% Usage:
%   s = mip.env.active()
%
% Returns [] when no environment is active. Otherwise returns a struct
% with fields:
%   root           - absolute path of the active environment's root
%   name           - environment name for named envs, '' for path envs
%   saved_mip_root - MIP_ROOT value before activation ('' if it was unset)
%   saved_loaded   - MIP_LOADED_PACKAGES before activation (in load order)
%   saved_direct   - MIP_DIRECTLY_LOADED_PACKAGES before activation
%   saved_sticky   - MIP_STICKY_PACKAGES before activation
%
% Activation is session state (persistent storage), like the loaded /
% sticky package lists.

s = mip.state.key_value_get('MIP_ENV_STATE');
if ~isstruct(s)
    s = [];
end

end
