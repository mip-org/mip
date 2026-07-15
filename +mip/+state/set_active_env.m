function set_active_env(env)
%SET_ACTIVE_ENV   Set or clear the active environment.
%
% Usage:
%   mip.state.set_active_env(env)   - env struct as returned by get_active_env
%   mip.state.set_active_env([])    - clear (no environment active)

if isempty(env)
    if isappdata(0, 'MIP_ACTIVE_ENV')
        rmappdata(0, 'MIP_ACTIVE_ENV');
    end
    return
end

setappdata(0, 'MIP_ACTIVE_ENV', env);

end
