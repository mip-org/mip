function restore_session(saved)
%RESTORE_SESSION   Reload a saved session package set.
%
% Usage:
%   mip.env.restore_session(saved)
%
% Puts a saved package set back on the path with its prior direct/sticky
% flags. saved is a struct with fields loaded, directly_loaded, and
% sticky (FQN cell arrays), as captured by mip.activate or
% mip.project.run before their session swap. Best-effort: failures warn
% (e.g. a package uninstalled meanwhile by another MATLAB session) and
% restoration continues with the remaining packages.

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
        warning('mip:env:restoreFailed', ...
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
