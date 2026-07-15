function env = get_active_env()
%GET_ACTIVE_ENV   Get the active environment, or [] when none is active.
%
% Usage:
%   env = mip.state.get_active_env()
%
% Returns a struct with fields:
%   name  - Environment name ('' for path environments)
%   path  - Absolute path of the environment root
%   saved - Session state captured at activation (mip_root, loaded,
%           directly_loaded, sticky), restored by mip.deactivate.
%
% Like the load-state lists, this is session state stored in appdata and
% is unaffected by "clear all".

env = getappdata(0, 'MIP_ACTIVE_ENV');
if ~isstruct(env)
    env = [];
end

end
