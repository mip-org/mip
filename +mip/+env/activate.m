function activate(varargin)
%ACTIVATE   Point this MATLAB session at a project environment and load it.
%
% Usage:
%   mip env activate
%   mip env activate --directory <dir>
%   mip env activate --no-load
%
% Options:
%   --directory <dir>  Project directory (default: current).
%   --no-load          Set the environment as active but don't add its
%                      packages to the MATLAB path.
%
% Sets MIP_ROOT for the current session to the project's .mip root, so
% subsequent mip commands (install, load, update, ...) operate on this
% environment. Ensures the environment is synced, then loads every directly
% requested package (and its dependencies) onto the MATLAB path.
%
% The activation lasts for the MATLAB session. To leave the environment,
% run "mip env deactivate" (or restart MATLAB).

    [opts, positionals] = mip.parse.flags(varargin, ...
        struct('directory', '', 'no_load', false));
    if ~isempty(positionals)
        error('mip:env:unexpectedArg', ...
              'Unexpected argument: %s', positionals{1});
    end

    projectDir = mip.env.project_dir(opts.directory);
    if ~exist(mip.env.spec_path(projectDir), 'file')
        error('mip:env:noSpec', ...
              'No mipenv.yaml in "%s". Run "mip env init" first.', projectDir);
    end
    root = mip.env.env_root(projectDir, true);

    % Set MIP_ROOT for the rest of the session (not restored on return).
    setenv('MIP_ROOT', root);
    fprintf('Activated environment: %s\n', projectDir);
    fprintf('MIP_ROOT = %s\n', root);

    % Ensure everything in the lock is installed. sync's own with_root saves
    % and restores the same value we just set, so MIP_ROOT stays put.
    mip.env.sync('--directory', projectDir);

    if opts.no_load
        fprintf('\nEnvironment active (packages not loaded; --no-load).\n');
        return
    end

    lockData = mip.env.read_lock(projectDir);
    fprintf('\nLoading packages...\n');
    loaded = 0;
    for i = 1:numel(lockData.packages)
        entry = lockData.packages{i};
        if isfield(entry, 'direct') && entry.direct
            mip.load(entry.fqn);
            loaded = loaded + 1;
        end
    end
    if loaded == 0
        fprintf('(no directly requested packages to load)\n');
    end
end
