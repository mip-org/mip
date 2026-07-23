function deactivate(varargin)
%DEACTIVATE   Point the session back at the base root.
%
% Usage:
%   mip deactivate
%
% Unloads everything the active environment had loaded (the running mip
% excepted — gh/mip-org/core/mip, plus a loaded preview build of mip if
% one is shadowing it; see mip.self.running_mip_fqn),
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

s = mip.state.get_env_state();
if isempty(s)
    fprintf('No environment is active\n');
    return
end

runningMip = '';
if isfield(s, 'running_mip')
    runningMip = s.running_mip;
end

% Unload the environment's packages. Use the normal unload machinery when
% the environment still exists on disk (it clears MEX binaries so no DLL
% stays locked on Windows; it spares the running mip via the activation
% state); the sweep below is the backstop for anything left over,
% including the case where the environment was deleted out from under the
% session.
loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
if mip.paths.is_valid_root(s.root) && any_swappable(loaded, runningMip)
    mip.unload('--all', '--force');
end
sweep_env_path_entries(s.root);

% Reset to the baseline load state, keeping the running mip with its
% direct/sticky flags. The unload above already did this when it ran;
% doing it explicitly also covers the deleted-env path where it did not.
reset_to_baseline(runningMip);

% Restore the pointer and clear the activation state before reloading the
% saved package set, so those loads resolve against the base root.
setenv('MIP_ROOT', s.saved_mip_root);
mip.state.key_value_set('MIP_ENV_STATE', []);

fprintf('Deactivated environment: %s\n', mip.env.display_env(s));

restore_saved_packages(s);

end

function tf = any_swappable(loaded, runningMip)
% True if anything besides the running mip is loaded.
    other = ~strcmp(loaded, 'gh/mip-org/core/mip');
    if ~isempty(runningMip)
        other = other & ~strcmp(loaded, runningMip);
    end
    tf = any(other);
end

function reset_to_baseline(runningMip)
% Keep only the running mip in the session lists, preserving its flags;
% mip itself always remains loaded and sticky.
    keepSet = {'gh/mip-org/core/mip'};
    if ~isempty(runningMip)
        keepSet{end+1} = runningMip;
    end
    loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    direct = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
    sticky = mip.state.key_value_get('MIP_STICKY_PACKAGES');
    loaded = loaded(ismember(loaded, keepSet));
    direct = direct(ismember(direct, keepSet));
    sticky = sticky(ismember(sticky, keepSet));
    if ~ismember('gh/mip-org/core/mip', loaded)
        loaded{end+1} = 'gh/mip-org/core/mip';
    end
    if ~ismember('gh/mip-org/core/mip', sticky)
        sticky{end+1} = 'gh/mip-org/core/mip';
    end
    mip.state.key_value_set('MIP_LOADED_PACKAGES', loaded);
    mip.state.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', direct);
    mip.state.key_value_set('MIP_STICKY_PACKAGES', sticky);
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
        % The running mip stayed loaded through the whole activation, so
        % it (like the core identity) needs no restoring.
        if strcmp(fqn, 'gh/mip-org/core/mip') || mip.state.is_loaded(fqn)
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
