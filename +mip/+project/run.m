function run(varargin)
%RUN   Lock if stale, sync, run a target inside the project env, restore.
%
% Usage:
%   mip project run <script.m>            - Run a script (path or *.m)
%   mip project run <function> [args...]  - Call a function, command syntax
%   mip project run "<expression>"        - Evaluate an expression
%   mip project run --locked <target>     - Error instead of re-locking
%   mip project run --no-sync <target>    - Run against what is installed
%   mip project run --with <pkg> <target> - Also install extra packages
%
% The mip analog of "uv run": makes sure the project is locked and
% synced, activates its environment for the duration of the run only,
% executes the target, and restores the session. Where "mip activate"
% changes the session until further notice, run is scoped: on return -
% normal or error - the MATLAB path, load state, and mip root are what
% they were before.
%
% The four steps:
%   1. Lock: if mip.lock is missing or stale (its recorded mip.yaml hash
%      no longer matches), re-lock. With --locked, error instead - in
%      CI, an implicit re-resolve should be a failure.
%   2. Sync: as "mip project sync" (dev group included), plus any --with
%      packages - installed into the project env but recorded nowhere,
%      so the next plain sync removes them. --with is repeatable and
%      takes the "mip install" package syntax. --no-sync skips this step
%      and runs against whatever is installed (erroring if a locked
%      package is missing); it cannot be combined with --with.
%   3. Activate, scoped: the same full swap as "mip activate --load",
%      guarded so the session is restored on the way out.
%   4. Run and restore: execute the target, then restore the previous
%      MIP_ROOT, MATLAB path, and load state, rethrowing any error.
%
% The target is disambiguated syntactically:
%   - a script: anything containing a path separator or ending in .m,
%     executed with "run" from the directory it lives in;
%   - a function call: a bare identifier, optionally followed by
%     arguments, evaluated as MATLAB command syntax - so
%     "mip project run f 3" is f('3') and every argument arrives as
%     char (for non-char arguments, or arguments starting with --, use
%     the expression form);
%   - an expression: anything else, in quotes.
%
% Every form executes in a scoped, throwaway workspace: mip never
% injects variables into the base workspace, so a target's output is
% what it displays or writes to disk. Restoration is best-effort by
% design: mip-managed state (root, path, load state) is guaranteed, but
% a run can still leak javaaddpath entries, globals, or loaded MEX
% files, and parpool workers do not inherit the temporarily modified
% path. For full isolation run from the shell:
%   matlab -batch "mip project run ..."

    [opts, args] = mip.parse.flags(varargin, ...
        struct('locked', false, 'no_sync', false, 'with', {{}}, 'directory', ''));
    if isempty(args)
        error('mip:project:noTarget', ...
              ['A target is required: a script path, a function name, ' ...
               'or a quoted expression.']);
    end
    if opts.no_sync && ~isempty(opts.with)
        error('mip:project:conflictingFlags', ...
              '--with installs packages during the sync step; it cannot be combined with --no-sync.');
    end
    target = args{1};
    extraArgs = args(2:end);

    proj = mip.project.locate(opts.directory);

    % 1. Lock if stale.
    if lock_is_stale(proj)
        if opts.locked
            error('mip:project:lockStale', ...
                  ['mip.lock is missing or out of date with mip.yaml ' ...
                   '(--locked). Run "mip project lock" and commit the result.']);
        end
        mip.project.lock_project(proj, false);
    end

    % 2. Sync (dev group included by default), plus --with packages.
    if opts.no_sync
        assert_env_complete(proj);
    else
        mip.project.sync_project(proj, struct('with', {opts.with}));
    end

    % 3. Scoped activation: save the session, swap to the project env.
    saved = struct();
    saved.mip_root        = getenv('MIP_ROOT');
    saved.loaded          = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    saved.directly_loaded = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
    saved.sticky          = mip.state.key_value_get('MIP_STICKY_PACKAGES');
    saved.active_env      = mip.state.get_active_env();

    mip.unload('--all', '--force');
    setenv('MIP_ROOT', proj.env_path);
    mip.state.set_active_env(struct('name', '', 'path', proj.env_path, ...
                                    'saved', rmfield(saved, 'active_env')));
    restoreGuard = onCleanup(@() restore_session(saved, proj.env_path)); %#ok<NASGU>

    mip.env.load_direct();
    for i = 1:numel(opts.with)
        w = mip.parse.parse_package_arg(opts.with{i});
        try
            if w.is_fqn
                mip.load(w.fqn);
            else
                mip.load(w.name);
            end
        catch ME
            fprintf('Failed to load --with package "%s": %s\n', ...
                    opts.with{i}, ME.message);
        end
    end

    % 4. Run. The guard restores the session on the way out, normal
    % return and error alike.
    fprintf('Running: %s\n', strjoin([{target}, extraArgs], ' '));
    mip.project.exec_target(target, extraArgs);

end

function stale = lock_is_stale(proj)
% Missing lock, unreadable lock, or a spec-hash mismatch. An empty hash
% on either side (no JVM) reads as "cannot tell" - not stale.
    if ~isfile(proj.lock_path)
        stale = true;
        return
    end
    try
        lockData = mip.project.read_lock(proj.lock_path);
    catch
        stale = true;
        return
    end
    specHash = mip.project.spec_hash(proj.dir);
    stale = ~isempty(specHash) && ~isempty(lockData.spec_sha256) ...
            && ~strcmp(specHash, lockData.spec_sha256);
end

function assert_env_complete(proj)
% --no-sync: the run uses whatever is installed, but a missing locked
% package (base + dev selection) is an error rather than a late failure.
    if ~mip.env.is_env(proj.env_path)
        error('mip:project:envMissing', ...
              ['The project environment %s does not exist. Run ' ...
               '"mip project sync" (or drop --no-sync).'], ...
              mip.env.display_path(proj.env_path));
    end
    lockData = mip.project.read_lock(proj.lock_path);
    missing = {};
    for i = 1:numel(lockData.packages)
        e = lockData.packages{i};
        if ~(e.base || ismember('dev', e.groups))
            continue
        end
        parts = strsplit(e.fqn, '/');
        pkgDir = fullfile(proj.env_path, 'packages', parts{:});
        if ~isfolder(pkgDir)
            missing{end+1} = mip.parse.display_fqn(e.fqn); %#ok<AGROW>
        end
    end
    if ~isempty(missing)
        error('mip:project:envIncomplete', ...
              ['Locked package(s) missing from the environment (--no-sync): ' ...
               '%s. Run "mip project sync".'], strjoin(missing, ', '));
    end
end

function restore_session(saved, envPath)
% Undo the scoped activation: unload the run's packages, sweep any
% leftover env path entries, and restore the saved root pointer, active
% environment, and package set. Best-effort throughout.
    try
        mip.unload('--all', '--force');
    catch
        mip.state.key_value_set('MIP_LOADED_PACKAGES', {'gh/mip-org/core/mip'});
        mip.state.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', {});
        mip.state.key_value_set('MIP_STICKY_PACKAGES', {'gh/mip-org/core/mip'});
    end
    mip.env.sweep_path_entries(envPath);
    setenv('MIP_ROOT', saved.mip_root);
    mip.state.set_active_env(saved.active_env);
    mip.env.restore_session(saved);
end

