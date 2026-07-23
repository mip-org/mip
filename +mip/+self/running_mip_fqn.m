function fqn = running_mip_fqn()
%RUNNING_MIP_FQN   The loaded package providing the running mip, or ''.
%
% Usage:
%   fqn = mip.self.running_mip_fqn()
%
% Normally the running mip is gh/mip-org/core/mip, which has its own
% FQN-based identity protections; this helper covers the case where a
% DIFFERENT loaded package provides the mip code actually running — e.g.
% a preview build (gh/mip-org/labs/mip) installed and loaded over the
% released mip. Implicit unloads (the activation swap, deactivate,
% unload --all --force, reset, transitive-dependency pruning) spare that
% package like the core identity, so they never pull the running mip off
% the path. An explicit `mip unload` of it remains allowed — that is how
% a preview build is exited.
%
% While an environment is active, the value detected at activation time
% (against the root the package was loaded from) is used: the package is
% not installed in the environment, so live detection there would fail.
% Otherwise, the mip.m locations reported by which('mip', '-all') are
% walked in path (precedence) order, and the first one lying inside a
% loaded package's source tree identifies that package as the provider —
% so when several loaded packages ship a mip.m, the copy that wins
% shadowing (the most recently loaded) is the one returned. Locations
% belonging to no loaded package (e.g. a mip.m in the user's current
% folder, or the installed core mip) are skipped, which keeps the check
% robust to stray shadowing, like mip.self.is_own_root's membership
% test. Never returns the core identity itself.

s = mip.state.get_env_state();
if ~isempty(s)
    if isfield(s, 'running_mip')
        fqn = s.running_mip;
    else
        fqn = '';
    end
    return
end

fqn = '';

loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
loaded = loaded(~strcmp(loaded, 'gh/mip-org/core/mip'));
if isempty(loaded)
    return
end

candidates = which('mip', '-all');
candDirs = cell(1, numel(candidates));
for i = 1:numel(candidates)
    candDirs{i} = strip_trailing_sep(fileparts(candidates{i}));
end

% Resolve each loaded package's source directory once (a package whose
% source cannot be resolved keeps an empty entry and never matches).
srcDirs = cell(1, numel(loaded));
for i = 1:numel(loaded)
    try
        pkgDir = mip.paths.get_package_dir(loaded{i});
        if ~isfolder(pkgDir)
            continue
        end
        pkgInfo = mip.config.read_package_json(pkgDir);
        srcDir = mip.paths.get_source_dir(pkgDir, pkgInfo);
    catch
        continue
    end
    srcDirs{i} = strip_trailing_sep(srcDir);
end

% Walk the mip.m locations in path (precedence) order: the first one
% belonging to a loaded package is the copy that wins shadowing — the
% mip actually running. Locations under no loaded package (the user's
% current folder, the installed core mip) are skipped.
for k = 1:numel(candDirs)
    for i = 1:numel(loaded)
        if ~isempty(srcDirs{i}) && path_is_under(candDirs{k}, srcDirs{i})
            fqn = loaded{i};
            return
        end
    end
end

end

function tf = path_is_under(child, parent)
% child equals parent, or lies inside parent's tree.
    if ispc
        tf = strcmpi(child, parent) || strncmpi(child, [parent filesep], length(parent) + 1);
    else
        tf = strcmp(child, parent) || strncmp(child, [parent filesep], length(parent) + 1);
    end
end

function p = strip_trailing_sep(p)
    while length(p) > 1 && (p(end) == '/' || p(end) == '\')
        p = p(1:end-1);
    end
end
