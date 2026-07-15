function sync_project(proj, opts)
%SYNC_PROJECT   Make a project's .mip environment match its mip.lock.
%
% The machinery behind "mip project sync" and the sync steps of
% "mip project add/remove/run". Installs each selected lock entry
% directly from its recorded mhl_url (verifying mhl_sha256 when the lock
% carries one), removes installed packages the lock does not select, and
% reconciles the directly-installed flags - so the environment is a
% disposable copy of the lock, rebuilt identically on any machine.
%
% Selection: the base dependency closure plus the dev group by default;
% opts.no_dev skips dev, opts.group adds groups, opts.all_groups selects
% every group. Entries locked for another architecture re-resolve at the
% locked version for this architecture.
%
% When the spec carries package identity (name:), sync finishes by
% installing the project itself into the environment as an editable
% install - the uv sync behavior - and never prunes it.
%
% The first sync of a formerly hand-managed environment (no sync stamp
% yet) that would remove packages lists them and confirms first
% (opts.yes skips; the MIP_CONFIRM environment variable is honored).
%
% Args:
%   proj - Project struct from mip.project.locate
%   opts - Struct with fields (all optional):
%     no_dev     - Skip the dev group (default false)
%     group      - Cell array of extra group names to select (default {})
%     all_groups - Select every group (default false)
%     yes        - Skip the first-prune confirmation (default false)
%     with       - Cell array of extra package args to install into the
%                  env, recorded nowhere (default {}; used by "run")

if nargin < 2
    opts = struct();
end
opts = apply_defaults(opts, struct('no_dev', false, 'group', {{}}, ...
                                   'all_groups', false, 'yes', false, ...
                                   'with', {{}}));

lockData = mip.project.read_lock(proj.lock_path);
spec = mip.project.read_spec(proj.dir);

selection = select_groups(spec, lockData, opts);
targets = {};
for i = 1:numel(lockData.packages)
    e = lockData.packages{i};
    if e.base || ~isempty(intersect(e.groups, selection))
        targets{end+1} = e; %#ok<AGROW>
    end
end
targetFqns = cellfun(@(e) e.fqn, targets, 'UniformOutput', false);

% Materialize the environment (marker and all) if it does not exist.
if mip.env.materialize(proj.env_path)
    fprintf('Created environment at %s\n', mip.env.display_path(proj.env_path));
end

% Whether this session's active root IS the project env decides whether
% packages must be unloaded before removal/replacement: load state is
% session-global and FQN-keyed, so unloading here would otherwise rip a
% same-named package loaded from a different root off the path.
try
    sessionRoot = mip.paths.root();
catch
    sessionRoot = '';
end
sessionOwnsEnv = ~isempty(sessionRoot) && mip.paths.is_same(sessionRoot, proj.env_path);

% Point every state/path helper at the project env for the duration.
priorRoot = getenv('MIP_ROOT');
restoreRoot = onCleanup(@() setenv('MIP_ROOT', priorRoot)); %#ok<NASGU>
setenv('MIP_ROOT', proj.env_path);

installed = mip.state.list_installed_packages();

% Keep set: the selected lock entries, plus the project's own editable
% install when the spec is a named package.
keepFqns = targetFqns;
if ~isempty(spec.name)
    keepFqns = [keepFqns, {['local/' spec.name]}];
end
toRemove = installed(~ismember(installed, keepFqns));

% First-prune confirmation for a formerly hand-managed env.
stampPath = fullfile(proj.env_path, 'mip-sync.json');
if ~isempty(toRemove) && ~isfile(stampPath) && ~opts.yes
    fprintf('This environment was not built by "mip project sync". The following\n');
    fprintf('installed packages are not selected by mip.lock and will be removed:\n');
    for i = 1:numel(toRemove)
        fprintf('  - %s\n', mip.parse.display_fqn(toRemove{i}));
    end
    if ~confirm_prompt()
        error('mip:project:syncAborted', 'Sync aborted.');
    end
end

% Remove packages the lock does not select.
nRemoved = 0;
for i = 1:numel(toRemove)
    remove_package(toRemove{i}, sessionOwnsEnv);
    nRemoved = nRemoved + 1;
end

% Install / replace the selected entries, dependency-first.
currentArch = mip.build.arch();
nInstalled = 0;
nReplaced = 0;
for i = 1:numel(targets)
    e = targets{i};
    pkgDir = mip.paths.get_package_dir(e.fqn);
    if isfolder(pkgDir)
        info = mip.config.read_package_json(pkgDir);
        if strcmp(info.version, e.version)
            continue
        end
        fprintf('Replacing "%s" %s with locked version %s...\n', ...
                mip.parse.display_fqn(e.fqn), info.version, e.version);
        remove_package(e.fqn, sessionOwnsEnv);
        install_entry(e, pkgDir, currentArch);
        nReplaced = nReplaced + 1;
    else
        install_entry(e, pkgDir, currentArch);
        nInstalled = nInstalled + 1;
    end
end

% Reconcile the directly-installed flags with the lock.
for i = 1:numel(targets)
    e = targets{i};
    if e.direct
        mip.state.add_directly_installed(e.fqn);
    else
        mip.state.remove_directly_installed(e.fqn);
    end
end

% A named spec is simultaneously the project's own package: install it
% editable, with the lock-provided dependencies already in place.
if ~isempty(spec.name) && ~isfolder(mip.paths.get_package_dir(['local/' spec.name]))
    fprintf('Installing project package "%s" (editable)...\n', spec.name);
    try
        mip.install.from_local(proj.dir, true, false, 'local');
    catch ME
        error('mip:project:selfInstallFailed', ...
              ['Could not install the project package "%s" (editable): %s\n' ...
               'A named mip.yaml is simultaneously a mip package (see ' ...
               '"mip init"); fix its package fields, or remove name: to ' ...
               'keep a plain project spec.'], ...
              spec.name, ME.message);
    end
end

% Stamp the env as sync-managed, recording which lock it was built from.
write_stamp(stampPath, proj.lock_path, selection);

% Extra --with packages: installed into the env but recorded nowhere, so
% the next plain sync removes them.
if ~isempty(opts.with)
    fprintf('Installing --with package(s): %s\n', strjoin(opts.with, ', '));
    mip.install.from_repository(opts.with, '', false);
end

if nInstalled == 0 && nReplaced == 0 && nRemoved == 0
    fprintf('Environment matches mip.lock (%d package(s)).\n', numel(targets));
else
    fprintf('Synced %s: %d installed, %d replaced, %d removed (%d package(s) total).\n', ...
            mip.env.display_path(proj.env_path), nInstalled, nReplaced, ...
            nRemoved, numel(targets));
end

end

function selection = select_groups(spec, lockData, opts)
% Resolve the selected group names: dev by default (when it exists),
% plus opts.group, or every group with opts.all_groups. Group names are
% validated against the spec and the lock.
    known = fieldnames(spec.dependency_groups)';
    for i = 1:numel(lockData.packages)
        known = [known, lockData.packages{i}.groups]; %#ok<AGROW>
    end
    known = unique(known, 'stable');

    if opts.all_groups
        selection = known;
        return
    end

    selection = {};
    if ~opts.no_dev && ismember('dev', known)
        selection{end+1} = 'dev';
    end
    for i = 1:numel(opts.group)
        g = opts.group{i};
        if ~ismember(g, known)
            error('mip:project:unknownGroup', ...
                  'Unknown dependency group "%s". Known groups: %s', ...
                  g, group_list(known));
        end
        if ~ismember(g, selection)
            selection{end+1} = g; %#ok<AGROW>
        end
    end
end

function s = group_list(known)
    if isempty(known)
        s = '(none)';
    else
        s = strjoin(known, ', ');
    end
end

function remove_package(fqn, sessionOwnsEnv)
% Remove one installed package from the env, unloading it first when
% this session's active root is the env (gh/mip-org/core/mip is always
% marked loaded but an env copy was never on the path, so it is skipped).
    if sessionOwnsEnv && mip.state.is_loaded(fqn) ...
            && ~strcmp(fqn, 'gh/mip-org/core/mip')
        try
            mip.unload(fqn);
        catch ME
            warning('mip:project:unloadFailed', ...
                    'Could not unload "%s" before removal: %s', ...
                    mip.parse.display_fqn(fqn), ME.message);
        end
    end
    fprintf('Removing "%s"...\n', mip.parse.display_fqn(fqn));
    mip.paths.remove_dir(mip.paths.get_package_dir(fqn));
    mip.state.remove_directly_installed(fqn);
    mip.state.remove_pinned(fqn);
    mip.paths.cleanup_package_parents(fqn);
end

function install_entry(e, pkgDir, currentArch)
% Download and install one locked entry into the active (env) root,
% straight from the lock - no resolution. An entry locked for another
% architecture re-resolves at the locked version for this architecture.
    url = e.mhl_url;
    sha = e.mhl_sha256;
    if ~(strcmp(e.architecture, 'any') || strcmp(e.architecture, currentArch))
        fprintf(['Entry "%s" is locked for architecture "%s"; re-resolving ' ...
                 'version %s for "%s"...\n'], ...
                mip.parse.display_fqn(e.fqn), e.architecture, e.version, currentArch);
        [url, sha] = resolve_for_arch(e);
    end
    if isempty(url)
        error('mip:project:lockInvalid', ...
              'Lock entry for "%s" has no mhl_url; re-run "mip project lock".', ...
              mip.parse.display_fqn(e.fqn));
    end

    fprintf('Downloading %s %s...\n', mip.parse.display_fqn(e.fqn), e.version);
    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rm_temp_dir(tempDir)); %#ok<NASGU>
    try
        mhlPath = mip.channel.download_mhl(url, tempDir, sha);
        verify_locked_digest(mhlPath, sha, e);
        stagingDir = fullfile(tempDir, 'staging');
        mip.channel.extract_mhl(mhlPath, stagingDir);
        parentDir = fileparts(pkgDir);
        if ~isfolder(parentDir)
            mkdir(parentDir);
        end
        movefile(stagingDir, pkgDir);
        fprintf('Installed "%s" %s\n', mip.parse.display_fqn(e.fqn), e.version);
    catch ME
        if isfolder(pkgDir)
            rmdir(pkgDir, 's');
        end
        rethrow(ME);
    end
end

function verify_locked_digest(mhlPath, sha, e)
% Verify a downloaded archive against the digest recorded in the lock.
% Install-time digest verification is suspended in download_mhl (channel
% publishing is not atomic; see mip-org/mip#201), but a lock is a
% reproducibility promise: the digest and URL were recorded from one
% index snapshot, so a mismatch at sync time means the archive changed
% since locking, and the sync must fail. A lock without a digest, or a
% session without the JVM, skips the check.
    if isempty(sha)
        return
    end
    actual = mip.channel.sha256(mhlPath);
    if isempty(actual)
        return  % JVM unavailable - unable to verify
    end
    if ~strcmpi(actual, sha)
        error('mip:digestMismatch', ...
              ['SHA-256 mismatch for "%s" %s\n  locked:   %s\n  actual:   %s\n' ...
               'The archive changed since mip.lock was written. Re-run ' ...
               '"mip project lock" if this is expected.'], ...
              mip.parse.display_fqn(e.fqn), e.version, sha, actual);
    end
end

function [url, sha] = resolve_for_arch(e)
% Re-resolve a lock entry at its locked version for the current
% architecture (v1 locks a single architecture; see MEP 9).
    parsed = mip.parse.parse_package_arg(e.fqn);
    ch = [parsed.owner '/' parsed.channel];
    index = mip.channel.fetch_index(ch);
    requested = containers.Map('KeyType', 'char', 'ValueType', 'any');
    requested(e.name) = e.version;
    [chMap, chUnavail] = mip.resolve.build_package_info_map( ...
        index, parsed.owner, parsed.channel, requested);
    if ~chMap.isKey(e.fqn)
        if chUnavail.isKey(e.fqn)
            error('mip:packageUnavailable', ...
                  ['Package "%s" %s is not available for architecture "%s". ' ...
                   'Available architectures: %s'], ...
                  mip.parse.display_fqn(e.fqn), e.version, mip.build.arch(), ...
                  strjoin(chUnavail(e.fqn), ', '));
        end
        error('mip:packageNotFound', ...
              'Package "%s" %s not found in channel %s', ...
              mip.parse.display_fqn(e.fqn), e.version, ch);
    end
    info = chMap(e.fqn);
    url = info.mhl_url;
    sha = '';
    if isfield(info, 'mhl_sha256') && ~isempty(info.mhl_sha256)
        sha = info.mhl_sha256;
    end
end

function write_stamp(stampPath, lockPath, selection)
% Record that this env is sync-managed and which lock built it. The
% lock hash lets "mip project status" detect "lock newer than env"
% drift; '' when the hash cannot be computed.
    stamp = struct();
    stamp.lock_sha256 = mip.channel.sha256(lockPath);
    if isempty(stamp.lock_sha256)
        stamp.lock_sha256 = '';
    end
    if isempty(selection)
        stamp.groups = reshape({}, 0, 1);
    else
        stamp.groups = reshape(selection, [], 1);
    end
    stamp.mip_version = mip.version();
    fid = fopen(stampPath, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to %s', stampPath);
    end
    fwrite(fid, jsonencode(stamp));
    fclose(fid);
end

function tf = confirm_prompt()
% Honors MIP_CONFIRM as a non-interactive override (matching uninstall
% and mip env delete).
    confirm = getenv('MIP_CONFIRM');
    if isempty(confirm)
        confirm = input('Proceed? (y/n): ', 's');
    end
    tf = strcmpi(confirm, 'y') || strcmpi(confirm, 'yes');
end

function opts = apply_defaults(opts, defaults)
    fields = fieldnames(defaults);
    for i = 1:numel(fields)
        if ~isfield(opts, fields{i})
            opts.(fields{i}) = defaults.(fields{i});
        end
    end
end

function rm_temp_dir(d)
    if isfolder(d)
        rmdir(d, 's');
    end
end
