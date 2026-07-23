function s = get_env_state()
%GET_ENV_STATE   Get the environment session state (MIP_ENV_STATE), or [].
%
% Usage:
%   s = mip.state.get_env_state()
%
% Returns [] when no environment is active. Otherwise returns a struct
% with fields:
%   root           - absolute path of the active environment's root
%   name           - environment name for named envs, '' for path envs
%   running_mip    - FQN of the loaded package providing the running mip,
%                    detected at activation time ('' if none; see
%                    mip.self.running_mip_fqn)
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
