function activate(varargin)
%ACTIVATE   Point the session at a mip environment.
%
% Usage:
%   mip activate                - Activate ./.mip in the current directory
%   mip activate <name>         - Activate a named env from <baseline root>/envs/
%   mip activate <path>         - Activate the environment at a path
%   mip activate ... --load     - Also load the env's directly installed packages
%
% A bare word is a name in the central store; anything containing a path
% separator is a path. The no-argument form acts on ./.mip in the current
% directory exactly - it never walks up the directory tree. In every form
% the target must be an environment: the directory exists, contains the
% mip-env.json marker written by "mip env create", and has a packages/
% subtree.
%
% Activation is exclusive (one environment at a time; activating another
% environment deactivates the current one first) and swaps the whole
% session:
%   1. The current session state is saved: the MIP_ROOT value and the
%      loaded / directly-loaded / sticky package lists.
%   2. Every loaded package is unloaded, sticky ones included (only mip
%      itself stays): path entries are removed and MEX binaries are
%      cleared, so no binary from another root stays locked.
%   3. MIP_ROOT is pointed at the environment (child processes - system()
%      calls, matlab -batch - inherit it).
%
% By default nothing is loaded afterward: like every mip root, an
% environment is never bulk-loaded, and packages are loaded selectively
% with "mip load". With --load, each of the environment's directly
% installed packages is loaded as a direct load (dependencies load
% transitively). Loading is best-effort: failures are reported and
% summarized, and the environment stays active regardless.
%
% Activating the already-active environment prints a message and stops,
% though --load still performs its load pass. Use "mip deactivate" to
% return to the baseline root, restoring the saved session state.
%
% "mip env activate" is an alias for this command.

    [opts, args] = mip.parse.flags(varargin, struct('load', false));
    if numel(args) > 1
        error('mip:activate:tooManyArgs', ...
              '"mip activate" takes at most one environment argument.');
    end

    if isempty(args)
        t = struct('kind', 'path', 'name', '', 'path', fullfile(pwd, '.mip'));
        createHint = 'mip env create';
    else
        t = mip.env.classify_arg(args{1});
        if strcmp(t.kind, 'name')
            createHint = ['mip env create ' t.name];
        else
            createHint = ['mip env create ' t.path];
        end
    end

    % Validate the target before touching any session state.
    if ~isfolder(t.path)
        error('mip:env:notFound', ...
              'No environment at %s. Create it with:\n  %s', t.path, createHint);
    end
    if ~mip.env.is_env(t.path)
        error('mip:env:notAnEnvironment', ...
              ['"%s" is not a mip environment (no mip-env.json marker). ' ...
               'Create one with:\n  %s'], t.path, createHint);
    end
    if ~isfolder(fullfile(t.path, 'packages'))
        error('mip:env:invalid', ...
              'Environment "%s" is missing its packages/ directory.', t.path);
    end

    active = mip.state.get_active_env();
    if ~isempty(active) && mip.paths.is_same(active.path, t.path)
        fprintf('Environment %s is already active\n', mip.env.describe(active));
        if opts.load
            loadEnvPackages();
        end
        return
    end
    if ~isempty(active)
        mip.deactivate();
    end

    % Save the session state to be restored by mip.deactivate. Because a
    % previously active environment was just deactivated, this is always
    % the baseline session's state - there is no activation stack.
    saved = struct();
    saved.mip_root        = getenv('MIP_ROOT');
    saved.loaded          = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    saved.directly_loaded = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
    saved.sticky          = mip.state.key_value_get('MIP_STICKY_PACKAGES');

    % Full swap: unload everything (sticky included; mip itself stays)
    % via the normal unload machinery, while the old root is still the
    % active one. This also resets the load-state lists to the baseline
    % (mip loaded and sticky).
    mip.unload('--all', '--force');

    % Point the session at the environment.
    setenv('MIP_ROOT', t.path);
    env = struct('name', t.name, 'path', t.path, 'saved', saved);
    mip.state.set_active_env(env);

    fprintf('Activated environment: %s\n', mip.env.describe(env));

    if opts.load
        loadEnvPackages();
    end

end

function loadEnvPackages()
% Load the environment's directly installed packages as direct loads
% (dependencies come in transitively, exactly as if the user had run
% "mip load" on each). Best-effort: the pointer swap has already
% completed, each failure prints the mip error, and a summary closes the
% command. The environment stays active regardless.

    direct = mip.state.get_directly_installed();
    direct = direct(~strcmp(direct, 'gh/mip-org/core/mip'));
    if isempty(direct)
        fprintf('No directly installed packages to load.\n');
        return
    end

    nLoaded = 0;
    nFailed = 0;
    for i = 1:numel(direct)
        try
            mip.load(direct{i});
            nLoaded = nLoaded + 1;
        catch ME
            nFailed = nFailed + 1;
            fprintf('Failed to load "%s": %s\n', ...
                    mip.parse.display_fqn(direct{i}), ME.message);
        end
    end
    if nFailed > 0
        fprintf('Loaded %d package(s), %d failed.\n', nLoaded, nFailed);
    else
        fprintf('Loaded %d package(s).\n', nLoaded);
    end
end
