function deactivate(varargin)
%DEACTIVATE   Point the session back at the baseline root.
%
% Usage:
%   mip deactivate
%
% Undoes "mip activate", restoring the session saved at activation time:
%   1. The environment's loaded packages are unloaded (mip itself stays).
%      This works even if the environment directory was deleted out from
%      under the session - any path entries the normal unload machinery
%      cannot resolve from disk are swept by prefix instead.
%   2. MIP_ROOT is restored to its saved value (an externally set custom
%      root, or unset).
%   3. The saved package set is reloaded with its prior direct/sticky
%      flags. Restoration is best-effort with warnings - e.g. a package
%      uninstalled meanwhile by another MATLAB session warns rather than
%      aborts.
%
% If no environment is active, prints a message and does nothing.
%
% "mip env deactivate" is an alias for this command.

    if ~isempty(varargin)
        error('mip:deactivate:tooManyArgs', '"mip deactivate" takes no arguments.');
    end

    env = mip.state.get_active_env();
    if isempty(env)
        fprintf('No environment is active.\n');
        return
    end

    % Unload the environment's packages (mip itself stays) while the env
    % is still the active root, so package dirs resolve for path removal
    % and MEX clearing. The sweep afterwards catches anything the normal
    % machinery could not resolve from disk. If the environment directory
    % was deleted out from under the session, the machinery cannot even
    % resolve the root - reset the load state to the baseline directly
    % and let the sweep remove the stale path entries.
    if isfolder(fullfile(env.path, 'packages'))
        mip.unload('--all', '--force');
    else
        mip.state.key_value_set('MIP_LOADED_PACKAGES', {'gh/mip-org/core/mip'});
        mip.state.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', {});
        mip.state.key_value_set('MIP_STICKY_PACKAGES', {'gh/mip-org/core/mip'});
    end
    sweepEnvPathEntries(env.path);

    % Restore the pre-activation root pointer ('' = unset).
    setenv('MIP_ROOT', env.saved.mip_root);
    mip.state.set_active_env([]);

    restoreSavedPackages(env.saved);

    fprintf('Deactivated environment: %s\n', mip.env.describe(env));

end

function sweepEnvPathEntries(envPath)
% Remove any remaining MATLAB path entries under the environment root.
% Backstop for an environment directory deleted out from under the
% session, where unload cannot resolve source dirs from mip.json.

    prefixWithSep = [envPath, filesep];
    entries = strsplit(path, pathsep);
    oldState = warning('off', 'MATLAB:rmpath:DirNotFound');
    restoreWarn = onCleanup(@() warning(oldState)); %#ok<NASGU>
    for k = 1:numel(entries)
        e = entries{k};
        if isempty(e)
            continue
        end
        if strcmp(e, envPath) || startsWith(e, prefixWithSep)
            rmpath(e);
        end
    end
end

function restoreSavedPackages(saved)
% Put the saved package set back on the path with its prior
% direct/sticky flags. Best-effort: failures warn and restoration
% continues with the remaining packages.

    for i = 1:numel(saved.loaded)
        pkg = saved.loaded{i};
        if strcmp(pkg, 'gh/mip-org/core/mip')
            continue  % always loaded
        end
        try
            if ismember(pkg, saved.directly_loaded)
                mip.load(pkg);
            else
                mip.load(pkg, '--transitive');
            end
        catch ME
            warning('mip:deactivate:restoreFailed', ...
                    'Could not restore package "%s": %s', ...
                    mip.parse.display_fqn(pkg), ME.message);
        end
    end

    % Restore sticky flags for whatever made it back on the path.
    for i = 1:numel(saved.sticky)
        pkg = saved.sticky{i};
        if mip.state.is_loaded(pkg) && ~mip.state.is_sticky(pkg)
            mip.state.key_value_append('MIP_STICKY_PACKAGES', pkg);
        end
    end
end
