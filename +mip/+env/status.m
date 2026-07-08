function status(varargin)
%STATUS   Show the project environment's spec, lock, and install state.
%
% Usage:
%   mip env status
%   mip env status --directory <dir>
%
% Options:
%   --directory <dir>  Project directory (default: current).
%
% Prints the declared dependencies (mipenv.yaml), the resolved lock
% (mipenv.lock) with per-package install status, and whether this MATLAB
% session is currently activated on the environment.

    [opts, positionals] = mip.parse.flags(varargin, struct('directory', ''));
    if ~isempty(positionals)
        error('mip:env:unexpectedArg', ...
              'Unexpected argument: %s', positionals{1});
    end

    projectDir = mip.env.project_dir(opts.directory);
    root = mip.env.env_root(projectDir);

    fprintf('Project:  %s\n', projectDir);
    fprintf('Env root: %s\n', root);

    if ~exist(mip.env.spec_path(projectDir), 'file')
        fprintf('\nNo mipenv.yaml. Run "mip env init".\n');
        return
    end
    spec = mip.env.read_spec(projectDir);

    fprintf('\nDeclared dependencies (mipenv.yaml):\n');
    if isempty(spec.dependencies)
        fprintf('  (none)\n');
    else
        for i = 1:numel(spec.dependencies)
            fprintf('  - %s\n', spec.dependencies{i});
        end
    end
    if ~isempty(spec.channels)
        fprintf('Channels: %s\n', strjoin(spec.channels, ', '));
    end

    if ~exist(mip.env.lock_path(projectDir), 'file')
        fprintf('\nNo mipenv.lock. Run "mip env lock" or "mip env sync".\n');
        return
    end
    lockData = mip.env.read_lock(projectDir);

    fprintf('\nLocked packages (mipenv.lock, arch %s):\n', get_arch(lockData));
    guard = mip.env.with_root(mip.env.env_root(projectDir, true)); %#ok<NASGU>
    for i = 1:numel(lockData.packages)
        p = lockData.packages{i};
        pkgDir = mip.paths.get_package_dir(p.fqn);
        if exist(pkgDir, 'dir')
            state = 'installed';
        else
            state = 'missing';
        end
        marker = ' ';
        if isfield(p, 'direct') && p.direct
            marker = '*';
        end
        fprintf('  %s %-32s %-10s %-14s (%s)\n', marker, ...
                mip.parse.display_fqn(p.fqn), p.version, p.architecture, state);
    end

    active = getenv('MIP_ROOT');
    fprintf('\n');
    if strcmp(active, root) || strcmp(active, mip.env.env_root(projectDir, false))
        fprintf('This session IS activated on this environment.\n');
    else
        fprintf('This session is NOT activated. Run: mip env activate --directory %s\n', ...
                projectDir);
    end
end

function a = get_arch(lockData)
    if isfield(lockData, 'arch') && ~isempty(lockData.arch)
        a = lockData.arch;
    else
        a = 'unknown';
    end
end
