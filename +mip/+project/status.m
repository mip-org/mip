function status(varargin)
%STATUS   Report the project, its mode, environment health, and drift.
%
% Usage:
%   mip project status           - Report on the nearest project
%   mip project status --check   - Error on drift (nonzero exit in -batch)
%
% Reports the resolved project, the mode (pip+venv when no mip.lock
% exists, uv when it does), the active environment, and any drift
% between the spec, the lock, and the installed environment:
%   - mip.yaml changed since mip.lock was written (run "mip project lock")
%   - mip.lock changed since the environment was synced, the environment
%     was never synced, locked packages are missing, or unrecorded
%     packages are present (run "mip project sync")
%
% --check turns drift into an error, so "matlab -batch" exits nonzero -
% the CI guard for a stale lock or environment.
%
% Bare "mip project" is an alias for this command.

    [opts, args] = mip.parse.flags(varargin, ...
        struct('check', false, 'directory', ''));
    if ~isempty(args)
        error('mip:project:tooManyArgs', '"mip project status" takes no arguments.');
    end

    proj = mip.project.locate(opts.directory);
    spec = mip.project.read_spec(proj.dir);

    if isempty(spec.name)
        fprintf('project: (nameless spec)\n');
    elseif isempty(spec.version)
        fprintf('project: %s\n', spec.name);
    else
        fprintf('project: %s %s\n', spec.name, spec.version);
    end

    env = mip.state.get_active_env();
    if isempty(env)
        fprintf('active environment: (none)\n');
    elseif mip.paths.is_same(env.path, proj.env_path)
        fprintf('active environment: %s [this project''s .mip]\n', ...
                mip.env.describe(env));
    else
        fprintf('active environment: %s\n', mip.env.describe(env));
    end

    drift = {};
    if ~isfile(proj.lock_path)
        fprintf('mode: pip+venv (no mip.lock; "mip project lock" opts in)\n');
        if mip.env.is_env(proj.env_path)
            fprintf('environment: %s (hand-managed)\n', ...
                    mip.env.display_path(proj.env_path));
        else
            fprintf('environment: not created\n');
        end
    else
        fprintf('mode: uv (mip.lock present)\n');
        drift = check_lock_and_env(proj, spec);
    end

    if isempty(drift)
        fprintf('status: ok\n');
    else
        for i = 1:numel(drift)
            fprintf('drift: %s\n', drift{i});
        end
        if opts.check
            error('mip:project:drift', ...
                  'Project drift detected (%d issue(s), --check).', numel(drift));
        end
    end

end

function drift = check_lock_and_env(proj, spec)
% Health of the spec -> lock -> environment chain, in uv mode.
    drift = {};

    try
        lockData = mip.project.read_lock(proj.lock_path);
    catch ME
        fprintf('lock: unreadable\n');
        drift{end+1} = sprintf('mip.lock is unreadable (%s); run "mip project lock"', ...
                               ME.message);
        return
    end
    nDirect = 0;
    for i = 1:numel(lockData.packages)
        nDirect = nDirect + lockData.packages{i}.direct;
    end
    fprintf('lock: %d package(s) (%d direct)\n', numel(lockData.packages), nDirect);

    % Spec vs lock: the lock records the hash of the mip.yaml it
    % resolved; an empty hash on either side reads as "cannot tell".
    specHash = mip.project.spec_hash(proj.dir);
    if ~isempty(specHash) && ~isempty(lockData.spec_sha256) ...
            && ~strcmp(specHash, lockData.spec_sha256)
        fprintf('spec vs lock: STALE\n');
        drift{end+1} = 'mip.yaml has changed since mip.lock was written; run "mip project lock"';
    else
        fprintf('spec vs lock: up to date\n');
    end

    % Lock vs environment.
    if ~mip.env.is_env(proj.env_path)
        fprintf('environment: not created\n');
        drift{end+1} = 'the project environment .mip has not been created; run "mip project sync"';
        return
    end

    stampPath = fullfile(proj.env_path, 'mip-sync.json');
    stamp = read_stamp(stampPath);
    if isempty(stamp)
        fprintf('environment: never synced\n');
        drift{end+1} = 'the environment was not built by "mip project sync"; run "mip project sync"';
    else
        lockHash = mip.channel.sha256(proj.lock_path);
        if ~isempty(lockHash) && ~isempty(stamp.lock_sha256) ...
                && ~strcmp(lockHash, stamp.lock_sha256)
            fprintf('environment: out of date\n');
            drift{end+1} = 'mip.lock has changed since the environment was synced; run "mip project sync"';
        else
            fprintf('environment: synced\n');
        end
    end

    drift = [drift, check_env_contents(proj, spec, lockData, stamp)];
end

function drift = check_env_contents(proj, spec, lockData, stamp)
% Light content check of the environment against the lock: selected
% packages missing or at the wrong version, and unrecorded extras (which
% the next sync removes). Selection follows the last sync's groups when
% stamped, the default (dev) otherwise.
    drift = {};

    if ~isempty(stamp) && isfield(stamp, 'groups')
        selection = stamp.groups;
    else
        selection = {'dev'};
    end

    priorRoot = getenv('MIP_ROOT');
    restoreRoot = onCleanup(@() setenv('MIP_ROOT', priorRoot)); %#ok<NASGU>
    setenv('MIP_ROOT', proj.env_path);

    keepFqns = {};
    missing = {};
    for i = 1:numel(lockData.packages)
        e = lockData.packages{i};
        if ~(e.base || ~isempty(intersect(e.groups, selection)))
            continue
        end
        keepFqns{end+1} = e.fqn; %#ok<AGROW>
        pkgDir = mip.paths.get_package_dir(e.fqn);
        if ~isfolder(pkgDir)
            missing{end+1} = mip.parse.display_fqn(e.fqn); %#ok<AGROW>
            continue
        end
        info = mip.config.read_package_json(pkgDir);
        if ~strcmp(info.version, e.version)
            missing{end+1} = sprintf('%s (%s installed, %s locked)', ...
                mip.parse.display_fqn(e.fqn), info.version, e.version); %#ok<AGROW>
        end
    end
    if ~isempty(spec.name)
        keepFqns{end+1} = ['local/' spec.name];
    end

    installed = mip.state.list_installed_packages();
    extras = installed(~ismember(installed, keepFqns));

    if ~isempty(missing)
        drift{end+1} = sprintf('missing from the environment: %s; run "mip project sync"', ...
                               strjoin(missing, ', '));
    end
    if ~isempty(extras)
        extrasDisplay = cellfun(@mip.parse.display_fqn, extras, 'UniformOutput', false);
        drift{end+1} = sprintf('unrecorded package(s) in the environment (the next sync removes them): %s', ...
                               strjoin(extrasDisplay, ', '));
    end
end

function stamp = read_stamp(stampPath)
    stamp = [];
    if ~isfile(stampPath)
        return
    end
    try
        stamp = jsondecode(fileread(stampPath));
    catch
        stamp = [];
        return
    end
    if ~isfield(stamp, 'lock_sha256') || isempty(stamp.lock_sha256)
        stamp.lock_sha256 = '';
    end
    if ~isfield(stamp, 'groups') || isempty(stamp.groups)
        stamp.groups = {};
    elseif ischar(stamp.groups)
        stamp.groups = {stamp.groups};
    elseif ~iscell(stamp.groups)
        stamp.groups = cellstr(stamp.groups);
    end
    stamp.groups = reshape(stamp.groups, 1, []);
end
