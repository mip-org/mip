function remove(varargin)
%REMOVE   Remove one or more dependencies from the project environment.
%
% Usage:
%   mip env remove <package> [<package> ...]
%   mip env remove --directory <dir> <package>
%   mip env remove <package> --no-sync
%
% Options:
%   --directory <dir>  Project directory (default: current).
%   --no-sync          Update mipenv.yaml and mipenv.lock but do not prune
%                      installed files.
%
% Removes the packages from mipenv.yaml (matching either the exact stored
% dependency string or the bare package name), re-resolves mipenv.lock, and
% prunes any now-unused packages from the project root. Analog of
% "uv remove".

    [opts, packages] = mip.parse.flags(varargin, ...
        struct('directory', '', 'no_sync', false));
    if isempty(packages)
        error('mip:env:noPackage', ...
              'At least one package name is required for "mip env remove".');
    end

    projectDir = mip.env.project_dir(opts.directory);
    spec = mip.env.read_spec(projectDir);

    for i = 1:numel(packages)
        [spec.dependencies, removed] = drop_dep(spec.dependencies, packages{i});
        if removed
            fprintf('Removed dependency: %s\n', packages{i});
        else
            fprintf('Not a dependency (skipped): %s\n', packages{i});
        end
    end

    mip.env.write_spec(projectDir, spec);

    root = mip.env.env_root(projectDir, true);
    guard = mip.env.with_root(root); %#ok<NASGU>

    if isempty(spec.dependencies)
        % Nothing left to resolve; write an empty lock and prune everything
        % that was only there for the environment.
        lockData = struct('lock_version', 1, ...
                          'generated_with_mip', mip.version(), ...
                          'arch', mip.build.arch(), ...
                          'requested', {{}}, 'channels', {{}}, 'packages', {{}});
        mip.env.write_lock(projectDir, lockData);
        directFqns = {};
    else
        lockData = mip.env.resolve_lock(spec);
        mip.env.write_lock(projectDir, lockData);
        directFqns = {};
        for i = 1:numel(lockData.packages)
            e = lockData.packages{i};
            if isfield(e, 'direct') && e.direct
                directFqns{end+1} = e.fqn; %#ok<AGROW>
            end
        end
    end

    % Reset the environment's directly-installed set to exactly the new
    % direct roots. Dropping the removed package from this set is what lets
    % prune reclaim it (and any deps now unused).
    mip.state.set_directly_installed(directFqns);

    if ~opts.no_sync
        mip.state.prune_unused_packages();
        mip.env.sync('--directory', projectDir);
    end
end

function [deps, removed] = drop_dep(deps, pkgArg)
% Remove entries matching pkgArg either exactly or by bare package name.
    removed = false;
    target = mip.parse.parse_package_arg(pkgArg);
    keep = true(1, numel(deps));
    for i = 1:numel(deps)
        if strcmp(deps{i}, pkgArg)
            keep(i) = false;
            removed = true;
            continue
        end
        d = mip.parse.parse_package_arg(deps{i});
        if strcmp(mip.name.normalize(d.name), mip.name.normalize(target.name))
            keep(i) = false;
            removed = true;
        end
    end
    deps = deps(keep);
end
