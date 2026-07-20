function deactivate(varargin)
%DEACTIVATE   Point the session back at the baseline root.
%
% Usage:
%   mip deactivate
%
% Unloads everything the active environment had loaded (mip excepted),
% restores MIP_ROOT to its pre-activation value (which may be an
% externally set custom root, or unset), and restores the saved package
% set: each formerly loaded package goes back on the path with its prior
% direct/sticky flags, in its prior load order, so path precedence is
% exactly what it was before activation. Restoration is best-effort with
% warnings (e.g. a package uninstalled meanwhile by another session
% warns rather than aborts).
%
% Works even if the environment directory was deleted out from under the
% session: path entries under the environment are swept rather than
% resolved from disk.

if ~isempty(varargin)
    error('mip:env:tooManyArgs', '"mip deactivate" takes no arguments.');
end

s = mip.env.active();
if isempty(s)
    fprintf('No environment is active\n');
    return
end

% Unload the environment's packages. Use the normal unload machinery when
% the environment still exists on disk (it clears MEX binaries so no DLL
% stays locked on Windows); the sweep below is the backstop for anything
% left over, including the case where the environment was deleted out
% from under the session.
loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
if mip.paths.is_root(s.root) && any(~strcmp(loaded, 'gh/mip-org/core/mip'))
    mip.unload('--all', '--force');
end
sweep_env_path_entries(s.root);

mip.state.key_value_set('MIP_LOADED_PACKAGES', {'gh/mip-org/core/mip'});
mip.state.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', {});
mip.state.key_value_set('MIP_STICKY_PACKAGES', {'gh/mip-org/core/mip'});

% Restore the pointer and clear the activation state before reloading the
% saved package set, so those loads resolve against the baseline root.
setenv('MIP_ROOT', s.saved_mip_root);
mip.state.key_value_set('MIP_ENV_STATE', []);

fprintf('Deactivated environment: %s\n', mip.env.describe(s));

restore_saved_packages(s);

end

function sweep_env_path_entries(envRoot)
% Remove any MATLAB path entries under the environment root. Silent when
% the unload above already cleaned everything up.
    prefixWithSep = [envRoot, filesep];
    entries = strsplit(path, pathsep);
    oldState = warning('off', 'MATLAB:rmpath:DirNotFound');
    restoreWarn = onCleanup(@() warning(oldState));
    for k = 1:numel(entries)
        e = entries{k};
        if isempty(e)
            continue
        end
        if strcmp(e, envRoot) || startsWith(e, prefixWithSep)
            rmpath(e);
        end
    end
end

function restore_saved_packages(s)
% Re-load the packages that were loaded before activation, in their
% original load order, with their prior direct/sticky flags. Because
% dependencies were originally loaded before their dependents, replaying
% the list in order reproduces the original path precedence.
    for i = 1:length(s.saved_loaded)
        fqn = s.saved_loaded{i};
        if strcmp(fqn, 'gh/mip-org/core/mip')
            continue
        end
        flags = {};
        if ~ismember(fqn, s.saved_direct)
            flags{end+1} = '--transitive'; %#ok<AGROW>
        end
        if ismember(fqn, s.saved_sticky)
            flags{end+1} = '--sticky'; %#ok<AGROW>
        end
        try
            mip.load(fqn, flags{:});
        catch ME
            warning('mip:env:restoreFailed', ...
                    'Could not restore package "%s": %s', ...
                    mip.parse.display_fqn(fqn), ME.message);
        end
    end
end
