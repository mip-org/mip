function reset()
%RESET   Reset mip to a clean state.
%
% Usage:
%   mip reset
%
% Unloads all packages (including sticky ones, excluding mip itself) and
% removes all MIP key-value stores from persistent storage. If an
% environment is active, the session is pointed back at the baseline root
% (the saved package set is intentionally not restored - reset means a
% clean state).

% Unload all packages (force mode: includes sticky packages). Runs while
% any active environment is still the active root, so its package dirs
% resolve for path removal and MEX clearing.
mip.unload('--all', '--force');

% Drop any active environment: restore the pre-activation MIP_ROOT.
env = mip.state.get_active_env();
if ~isempty(env)
    setenv('MIP_ROOT', env.saved.mip_root);
end

% Remove all MIP key-value stores
keys = {'MIP_LOADED_PACKAGES', 'MIP_DIRECTLY_LOADED_PACKAGES', ...
        'MIP_STICKY_PACKAGES', 'MIP_TEST_CONTEXT', 'MIP_ACTIVE_ENV'};
for i = 1:length(keys)
    if isappdata(0, keys{i})
        rmappdata(0, keys{i});
    end
end

fprintf('mip has been reset\n');

end
