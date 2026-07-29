function update(varargin)
%UPDATE   Update one or more installed mip packages.
%
% Usage:
%   mip update <package>
%   mip update <owner>/<channel>/<package>
%   mip update <package1> <package2> ...
%   mip update --force <package>
%   mip update --deps <package>
%   mip update --all
%   mip update mip
%
% Options:
%   --force           Force update even if already up to date
%   --all             Update all installed packages
%   --deps            Also update the dependencies of the named packages
%   --no-compile      Skip compilation when updating editable local installs
%
% For each requested package, checks whether an update is needed. For
% remote packages, the installed version (and build timestamp) is compared
% against the latest in the channel index. Local packages are always
% considered to need an update. If a package does not need updating,
% nothing happens for that package (unless --force is specified).
%
% Remote packages are updated via staging: the new version is downloaded
% to a temporary directory first, then the old directory is replaced only
% after the download succeeds. Existing dependencies are not updated
% (unless --deps is specified). After the update, any missing dependencies
% that the updated package requires are installed, and any orphaned
% packages (old dependencies no longer needed by any directly installed
% package) are pruned.
%
% Local packages are reinstalled from their source path without going
% through uninstall (which would prune still-needed dependencies
% mid-update). Missing channel dependencies declared in mip.yaml are
% installed as part of the reinstall. The old package is backed up and
% restored if reinstall fails.
%
% Any packages that were loaded before the update are reloaded afterward.
%
% Accepts both bare package names and fully qualified names. Version
% specifiers are not accepted: update always stays on the installed
% version's branch or release stream. To switch to a different branch or
% version, use "mip install <package>@<version>" instead.
%
% "mip update mip" updates mip itself, in place, with no restart. It is
% allowed only from a plain session on the main root: not while an
% environment is active (deactivate first), not while another mip is
% loaded (unload it first), and not for a standalone mip (update the
% standalone copy directly).

    if nargin < 1
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    % Show the target when an environment is active (session state has no
    % shell prompt to reflect it).
    mip.env.print_banner();

    % Check for --force, --all, --deps, and --no-compile flags
    [opts, args] = mip.parse.flags(varargin, struct( ...
        'force', false, 'all', false, 'deps', false, 'no_compile', false));

    % Reject @version suffixes up front. Update always stays on the
    % installed version's branch or release stream (see
    % checkRemoteNeedsUpdate); switching to a different branch or version
    % requires an explicit "mip install <pkg>@<version>".
    for i = 1:length(args)
        parsed = mip.parse.parse_package_arg(args{i});
        if ~isempty(parsed.version)
            error('mip:update:versionNotAllowed', ...
                  ['A version specifier is not allowed with "mip update" ("%s"). ' ...
                   'To switch to a different branch or version, run: mip install %s'], ...
                  args{i}, args{i});
        end
    end

    % --all: expand to all installed packages. Pinned packages are
    % filtered up-front for --all (the user did not specify an explicit
    % order, so there is no per-arg position to anchor the skip messages
    % to). Explicitly named pinned packages are handled inside the main
    % per-package loop below so their skip messages appear in argument
    % order, interleaved with the unpinned packages' update output.
    if opts.all
        if ~isempty(args)
            error('mip:update:allWithPackages', ...
                  'Cannot specify package names with --all.');
        end
        allInstalled = mip.state.list_installed_packages();
        if isempty(allInstalled)
            fprintf('No packages installed.\n');
            return
        end
        % Pinned packages are always skipped, even with --force. To
        % update a pinned package, run "mip unpin <pkg>" first.
        % Packages that the self guards would refuse (the main mip while
        % it cannot be self-updated, or a loaded package providing the
        % running mip) are skipped with a message rather than aborting
        % the whole batch: no bulk operation ever errors on — or touches —
        % running code.
        selfState = mip.self.op_state();
        runningMip = mip.self.running_mip_fqn();
        filtered = {};
        nPinned = 0;
        for i = 1:length(allInstalled)
            fqn = allInstalled{i};
            if mip.state.is_pinned(fqn)
                nPinned = nPinned + 1;
                fprintf('Skipping pinned package "%s".\n', mip.parse.display_fqn(fqn));
            elseif strcmp(fqn, 'gh/mip-org/core/mip') && ...
                    any(strcmp(selfState.state, {'env', 'mip-loaded'}))
                fprintf('Skipping "%s": the main mip cannot be updated in this state (see "mip update mip").\n', ...
                        mip.parse.display_fqn(fqn));
            elseif ~isempty(runningMip) && strcmp(fqn, runningMip) && mip.state.is_loaded(fqn)
                fprintf('Skipping "%s": it provides the running mip. Run "mip unload %s" first.\n', ...
                        mip.parse.display_fqn(fqn), mip.parse.display_fqn(fqn));
            else
                filtered{end+1} = fqn; %#ok<AGROW>
            end
        end
        if isempty(filtered)
            if nPinned == length(allInstalled)
                fprintf('All packages are pinned. Nothing to update.\n');
            else
                fprintf('Nothing to update.\n');
            end
            return
        end
        args = filtered;
    end

    if isempty(args)
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    % --deps: expand the argument list with each package's dependencies.
    % Pinned dependencies are dropped from the expansion with a message.
    if opts.deps
        args = expandWithDeps(args);
    end

    % Pre-pass: classify each argument into a single per-arg item so the
    % main loop below can walk in argument order without revalidating.
    % Validation errors (not installed, missing source dir) are raised
    % here, before any destructive action — but the per-arg user-facing
    % messages (pin skip, no-source skip, "Checking for updates", etc.)
    % are deferred to the main loop so that one package's full lifecycle
    % output is not interleaved with the next.
    items = cell(1, length(args));
    for i = 1:length(args)
        items{i} = classifyArg(args{i});
    end

    % --no-compile only applies to editable local installs. Validate every
    % actionable item before any destructive action; the mip self-update is
    % never an editable local install, so it is rejected here rather than
    % falling through to the destructive updateSelf hot-swap. Restricting to
    % the actionable kinds matters: the skip kinds carry no .pkg (pin-skip)
    % or are not going to be built anyway (no-source-skip), so they must not
    % gate --no-compile.
    if opts.no_compile
        for i = 1:length(items)
            it = items{i};
            if any(strcmp(it.kind, {'process', 'self-update'})) && ~(it.pkg.isLocal && it.pkg.editable)
                error('mip:update:noCompileRequiresEditable', ...
                      '--no-compile can only be used when all updated packages are editable local installs (offending package: "%s").', ...
                      mip.parse.display_fqn(it.pkg.fqn));
            end
        end
    end

    % Snapshot currently-loaded state so we can restore it after the
    % update cycle.
    loadedBefore = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    directlyLoadedBefore = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');

    % Wrap the per-package loop in try-catch so that reloadPreviouslyLoaded
    % always runs. Without this, a failure mid-batch would leave
    % already-updated packages unloaded for the rest of the session.
    updatedRemoteFqns = {};
    updateError = [];
    try
        for i = 1:length(items)
            it = items{i};
            switch it.kind
                case 'pin-skip'
                    fprintf(['Skipping pinned package "%s". ' ...
                             'Run "mip unpin %s" first to allow updates.\n'], ...
                            it.displayFqn, it.displayFqn);
                case 'no-source-skip'
                    fprintf('Skipping "%s": no local source to update from.\n', ...
                            mip.parse.display_fqn(it.pkg.fqn));
                case 'standalone-skip'
                    fprintf(['The running mip is standalone — not installed in the main ' ...
                             'root — so mip does not manage its own files here.\n' ...
                             'Update the standalone copy itself (pull the checkout, or ' ...
                             'download a new copy).\n']);
                case 'self-update'
                    updateSelf(it.pkg, opts.force);
                case 'process'
                    p = it.pkg;
                    if p.isLocal
                        updateLocalPackage(p, opts.no_compile);
                    else
                        [needs, latestInfo] = checkRemoteNeedsUpdate(p, opts.force);
                        if ~needs
                            continue
                        end
                        mip.install.replace_installed(p.fqn, p.pkgDir, latestInfo);
                        fprintf('Successfully updated "%s" to %s\n', ...
                                mip.parse.display_fqn(p.fqn), latestInfo.version);
                        updatedRemoteFqns{end+1} = p.fqn; %#ok<AGROW>
                    end
            end
        end

        % Whole-batch operations: install any missing dependencies that
        % the updated remote packages now require, and prune orphans.
        if ~isempty(updatedRemoteFqns)
            installMissingDeps(updatedRemoteFqns);
            mip.state.prune_unused_packages();
        end
    catch ME
        updateError = ME;
    end

    % Reload anything that was loaded before update but isn't now.
    % This runs even after a partial failure so that successfully-updated
    % packages are not left unloaded.
    reloadPreviouslyLoaded(loadedBefore, directlyLoadedBefore);

    if ~isempty(updateError)
        rethrow(updateError);
    end
end

function item = classifyArg(packageArg)
% Classify a single argument into one of:
%   - pin-skip        : installed and pinned (named-explicit only; --all
%                       pre-filters, so reaching this branch implies the
%                       user named the package explicitly)
%   - self-update     : the gh/mip-org/core/mip identity, updatable here
%   - standalone-skip : the identity targeted while the running mip is
%                       standalone (not installed in the main root)
%   - no-source-skip  : local install with no recoverable source path
%   - process         : full update lifecycle should run
%
% Validation errors (not installed, missing source dir, self-op guards)
% are raised here, before any destructive action.
%
% The pin check resolves silently against installed packages — if the
% package is not installed, we fall through to resolvePackage so the
% standard mip:update:notInstalled error is raised.

    r = mip.resolve.resolve_to_installed(packageArg);
    if ~isempty(r) && mip.state.is_pinned(r.fqn)
        item = struct('kind', 'pin-skip', 'displayFqn', mip.parse.display_fqn(r.fqn));
        return
    end

    % Self-operation guards: updating the main mip is allowed only from a
    % plain session on the main root with no other mip loaded (see
    % specification §1.7.1). The identity is targeted by its FQN, or by a
    % bare "mip" that resolves to nothing installed (in the main root the
    % core mip is always installed, so an unresolved bare "mip" can only
    % mean the main mip in a root that does not hold it).
    parsed = mip.parse.parse_package_arg(packageArg);
    targetsIdentity = (~isempty(r) && strcmp(r.fqn, 'gh/mip-org/core/mip')) || ...
        (isempty(r) && (mip.self.is_identity(parsed) || ...
                        (~parsed.is_fqn && mip.name.match(parsed.name, 'mip'))));
    if targetsIdentity
        s = mip.self.op_state();
        switch s.state
            case 'ok'
                item = struct('kind', 'self-update', 'pkg', resolvePackage(packageArg));
                return
            case 'standalone'
                % No copy in this root: nothing to update; report why
                % (Scenario 14). With an inert copy installed here, fall
                % through — it is an ordinary remote package (its unload
                % step never applies; it is never loaded).
                if isempty(r)
                    item = struct('kind', 'standalone-skip');
                    return
                end
            case 'env'
                error('mip:self:envActive', ...
                      ['Cannot update the main mip while an environment is ' ...
                       'active. Run "mip deactivate" first.']);
            case 'mip-loaded'
                blockers = cellfun(@mip.parse.display_fqn, s.blockers, 'UniformOutput', false);
                error('mip:self:otherMipLoaded', ...
                      ['Cannot update the main mip while another mip is ' ...
                       'loaded (%s). Run "mip unload %s" first.'], ...
                      strjoin(blockers, ', '), blockers{end});
        end
    end

    p = resolvePackage(packageArg);

    % A package whose code is currently running cannot be updated while
    % loaded (Scenario 13): replacing it would pull the running mip's
    % files out from under the session.
    runningMip = mip.self.running_mip_fqn();
    if ~isempty(runningMip) && strcmp(p.fqn, runningMip) && mip.state.is_loaded(p.fqn)
        error('mip:update:runningMip', ...
              ['Package "%s" provides the running mip and cannot be updated ' ...
               'while it is loaded. Run "mip unload %s" first.'], ...
              mip.parse.display_fqn(p.fqn), mip.parse.display_fqn(p.fqn));
    end

    if p.noSource
        item = struct('kind', 'no-source-skip', 'pkg', p);
    else
        item = struct('kind', 'process', 'pkg', p);
    end
end

function updateLocalPackage(p, noCompile)
% Update a local package: backup, remove from directly_installed, then
% from_local from the original source path. Restore the backup if
% from_local fails. Local packages do NOT go through mip.uninstall
% because that would prune dependencies that are still needed while the
% package is momentarily absent.

    displayFqn = mip.parse.display_fqn(p.fqn);
    fprintf('Updating local package "%s"...\n', displayFqn);

    if mip.state.is_loaded(p.fqn)
        fprintf('Unloading "%s" before update...\n', displayFqn);
        mip.unload(p.fqn);
    end

    backupDir = mip.paths.backup_dir(p.pkgDir);
    mip.state.remove_directly_installed(p.fqn);
    mip.paths.cleanup_package_parents(p.fqn);

    fprintf('Reinstalling "%s" from %s...\n', displayFqn, p.sourcePath);
    try
        mip.install.from_local(p.sourcePath, p.editable, noCompile, p.type);
    catch ME
        mip.paths.restore_dir(backupDir, p.pkgDir);
        mip.state.add_directly_installed(p.fqn);
        rethrow(ME);
    end
    % The backup is the replaced old package; remove it robustly in case a
    % binary it shipped was loaded before the update.
    mip.paths.remove_dir(backupDir);
end

function p = resolvePackage(packageArg)
% Resolve a package argument to a struct with everything needed to
% update it. Validates that the package is installed and, for local
% packages, that the original source directory is still available.

    r = mip.resolve.resolve_to_installed(packageArg);
    if isempty(r)
        error('mip:update:notInstalled', ...
              'Package "%s" is not installed. Run "mip install %s" first.', ...
              packageArg, packageArg);
    end

    try
        pkgInfo = mip.config.read_package_json(r.pkg_dir);
    catch
        pkgInfo = struct('version', '', 'name', r.name);
    end

    % "Local" here means any non-gh source type (local, fex, or web). Update
    % treats them the same way: reinstall from source rather than from a
    % channel index.
    isLocal = ~strcmp(r.type, 'gh');
    sourcePath = '';
    editable = false;
    noSource = false;
    if isLocal
        if isfield(pkgInfo, 'source_path')
            sourcePath = pkgInfo.source_path;
        end
        % No source_path at all, or an empty one, means there is no local
        % source to reinstall from (e.g. URL installs clear it after
        % extracting into a temp dir). The main flow skips such packages
        % with a message rather than erroring.
        noSource = isempty(sourcePath);
        if ~noSource && ~isfolder(sourcePath)
            error('mip:update:sourceNotFound', ...
                  'Source directory "%s" for package "%s" no longer exists.', ...
                  sourcePath, mip.parse.display_fqn(r.fqn));
        end
        editable = isfield(pkgInfo, 'editable') && pkgInfo.editable;
    end

    p = struct( ...
        'fqn', r.fqn, ...
        'type', r.type, ...
        'owner', r.owner, ...
        'channel', r.channel, ...
        'name', r.name, ...
        'pkgDir', r.pkg_dir, ...
        'pkgInfo', pkgInfo, ...
        'isLocal', isLocal, ...
        'sourcePath', sourcePath, ...
        'editable', editable, ...
        'noSource', noSource ...
    );
end

function [tf, latestInfo] = checkRemoteNeedsUpdate(p, force)
% Fetch the channel index and decide whether p needs updating.
% Also returns the latestInfo struct (needed for downloading).

    fqn = p.fqn;
    displayFqn = mip.parse.display_fqn(fqn);
    installedVersion = p.pkgInfo.version;
    channelStr = [p.owner '/' p.channel];

    fprintf('Checking for updates to "%s"...\n', displayFqn);

    index = mip.channel.fetch_index(channelStr);

    % If the installed version is non-numeric (e.g. 'main', 'master'),
    % pin the update lookup to that branch or version.
    % Otherwise the default select_best_version would silently switch to
    % a higher-ranked numeric release the first time one appears in the
    % channel. Switching to a different branch or version requires an
    % explicit `mip install X@...`.
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    if ~isempty(installedVersion) && ~mip.resolve.is_numeric_version(installedVersion)
        requestedVersions(p.name) = installedVersion;
    end
    try
        [packageInfoMap, unavailablePackages] = mip.resolve.build_package_info_map( ...
            index, p.owner, p.channel, requestedVersions);
    catch err
        if strcmp(err.identifier, 'mip:versionNotFound')
            error('mip:update:versionNotInChannel', ...
                  ['Installed version "%s" of "%s" no longer exists in channel "%s". ' ...
                   'To switch to a different branch or version, run: mip install %s@<version>'], ...
                  installedVersion, fqn, channelStr, fqn);
        end
        rethrow(err);
    end

    currentArch = mip.build.arch();
    if ~packageInfoMap.isKey(fqn)
        if unavailablePackages.isKey(fqn)
            archs = unavailablePackages(fqn);
            error('mip:update:unavailable', ...
                  'Package "%s" is not available for architecture "%s". Available: %s', ...
                  p.name, currentArch, strjoin(archs, ', '));
        else
            error('mip:update:notInIndex', ...
                  'Package "%s" not found in the %s channel index.', ...
                  p.name, channelStr);
        end
    end

    latestInfo = packageInfoMap(fqn);

    if force
        fprintf('Force updating "%s" (%s)\n', displayFqn, installedVersion);
        tf = true;
        return
    end

    if ~mip.state.check_needs_update(p.pkgInfo, latestInfo)
        fprintf('Package "%s" is already up to date (%s)\n', displayFqn, installedVersion);
        tf = false;
        return
    end

    fprintf('Updating "%s": %s -> %s\n', displayFqn, installedVersion, latestInfo.version);
    tf = true;
end

function installMissingDeps(remoteFqns)
% Check the updated packages' dependencies and install any that are missing.

    missingDeps = {};
    for i = 1:length(remoteFqns)
        fqn = remoteFqns{i};
        pkgDir = mip.paths.get_package_dir(fqn);
        if ~exist(pkgDir, 'dir')
            continue
        end
        try
            pkgInfo = mip.config.read_package_json(pkgDir);
        catch
            continue
        end
        deps = pkgInfo.dependencies;
        if isempty(deps)
            continue
        end
        missingDeps = [missingDeps, mip.dependency.find_missing(deps, fqn)]; %#ok<AGROW>
    end
    missingDeps = unique(missingDeps, 'stable');

    if isempty(missingDeps)
        return
    end

    missingDisplay = cellfun(@mip.parse.display_fqn, missingDeps, 'UniformOutput', false);
    fprintf('\nInstalling missing dependencies: %s\n', strjoin(missingDisplay, ', '));

    % Install as transitive dependencies (not directly installed), so
    % they can be pruned when their dependents no longer need them.
    mip.install.from_repository(missingDeps, '', false);
end

function reloadPreviouslyLoaded(loadedBefore, directlyLoadedBefore)
% Reload any packages that were loaded before the update but are no
% longer loaded. Uses --transitive for packages that were not directly
% loaded, preserving the direct-vs-transitive distinction without
% needing a post-fixup pass.

    if isempty(loadedBefore)
        return
    end

    for i = 1:length(loadedBefore)
        pkg = loadedBefore{i};
        if mip.state.is_loaded(pkg)
            continue
        end
        r = mip.parse.parse_package_arg(pkg);
        if ~r.is_fqn
            continue
        end
        pkgDir = mip.paths.get_package_dir(pkg);
        displayPkg = mip.parse.display_fqn(pkg);
        if ~exist(pkgDir, 'dir')
            fprintf('Warning: "%s" was loaded before update but is no longer installed; skipping reload.\n', displayPkg);
            continue
        end
        fprintf('Reloading "%s"...\n', displayPkg);
        if ismember(pkg, directlyLoadedBefore)
            mip.load(pkg);
        else
            mip.load(pkg, '--transitive');
        end
    end
end

function updateSelf(p, force)
% Self-update for gh/mip-org/core/mip. mip cannot be uninstalled through
% the normal flow, so we download and swap in place.

    [needs, latestInfo] = checkRemoteNeedsUpdate(p, force);
    if ~needs
        return
    end

    % mip is the running code, so it can't be unloaded and reinstalled the
    % normal way — hand off to the shared in-place hot-swap.
    mip.self.hot_swap(p.pkgDir, p.pkgInfo, latestInfo);
    fprintf('Successfully updated "%s" to %s\n', ...
            mip.parse.display_fqn(p.fqn), latestInfo.version);
end

function expanded = expandWithDeps(args)
% Expand a list of package arguments to include their installed
% dependencies (recursively). The original packages come first, followed
% by any dependencies not already in the list. Pinned dependencies are
% dropped from the expansion with a message — only explicitly named
% packages can hit the pin error path.

    expanded = args;
    for i = 1:length(args)
        r = mip.resolve.resolve_to_installed(args{i});
        if isempty(r)
            % Not installed — will error later in resolvePackage; skip here
            continue
        end
        % Pinned explicit packages are dropped in the per-package loop
        % (with a "Skipping pinned package" message). Their dependencies
        % are not expanded — see spec §7.11.3.
        if mip.state.is_pinned(r.fqn)
            continue
        end
        deps = mip.dependency.find_all(r.fqn);
        for j = 1:length(deps)
            if ~mip.state.is_installed(deps{j}) || any(strcmp(expanded, deps{j}))
                continue
            end
            if mip.state.is_pinned(deps{j})
                fprintf('Skipping pinned dependency "%s".\n', mip.parse.display_fqn(deps{j}));
                continue
            end
            expanded{end+1} = deps{j}; %#ok<AGROW>
        end
    end
end
