function update(varargin)
%UPDATE   Update one or more installed mip packages.
%
% Usage:
%   mip.update('packageName')
%   mip.update('org/channel/packageName')
%   mip.update('package1', 'package2')
%   mip.update('--force', 'packageName')
%   mip.update('--deps', 'packageName')
%   mip.update('--all')
%   mip.update('mip')
%
% Options:
%   --force           Force update even if already up to date
%   --all             Update all installed packages
%   --deps            Also update the dependencies of the named packages
%   --no-compile      Skip compilation when updating editable local installs
%
% For each requested package, checks whether an update is needed. For
% remote packages, the installed version (and commit hash) is compared
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
% through uninstall (since install_local cannot re-fetch deps from a
% channel). The old package is backed up and restored if reinstall fails.
%
% Any packages that were loaded before the update are reloaded afterward.
%
% Accepts both bare package names and fully qualified names.

    if nargin < 1
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    % Check for --force, --all, --deps, and --no-compile flags
    force = false;
    updateAll = false;
    updateDeps = false;
    noCompile = false;
    args = {};
    for i = 1:length(varargin)
        arg = varargin{i};
        if ischar(arg) && strcmp(arg, '--force')
            force = true;
        elseif ischar(arg) && strcmp(arg, '--all')
            updateAll = true;
        elseif ischar(arg) && strcmp(arg, '--deps')
            updateDeps = true;
        elseif ischar(arg) && strcmp(arg, '--no-compile')
            noCompile = true;
        else
            args{end+1} = arg; %#ok<AGROW>
        end
    end

    % --all: update all installed packages
    if updateAll
        if ~isempty(args)
            error('mip:update:allWithPackages', ...
                  'Cannot specify package names with --all.');
        end
        allInstalled = mip.state.list_installed_packages();
        if isempty(allInstalled)
            fprintf('No packages installed.\n');
            return
        end
        % Skip pinned packages unless --force is set
        if ~force
            filtered = {};
            for i = 1:length(allInstalled)
                if mip.state.is_pinned(allInstalled{i})
                    fprintf('Skipping pinned package "%s".\n', mip.parse.display_fqn(allInstalled{i}));
                else
                    filtered{end+1} = allInstalled{i}; %#ok<AGROW>
                end
            end
            allInstalled = filtered;
        end
        if isempty(allInstalled)
            fprintf('All packages are pinned. Nothing to update.\n');
            return
        end
        args = allInstalled;
    end

    if isempty(args)
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    % --deps: expand the argument list with each package's dependencies
    if updateDeps
        args = expandWithDeps(args);
    end

    % Resolve and validate each argument. Any error here (not installed,
    % missing source dir) is raised before we touch anything on disk.
    resolved = cell(1, length(args));
    for i = 1:length(args)
        resolved{i} = resolvePackage(args{i});
    end

    % Skip local packages with no available source (e.g. URL installs).
    % They cannot be reinstalled, so update them is a no-op with a message.
    toProcess = {};
    for i = 1:length(resolved)
        p = resolved{i};
        if p.noSource
            fprintf('Skipping "%s": no local source to update from.\n', mip.parse.display_fqn(p.fqn));
        else
            toProcess{end+1} = p; %#ok<AGROW>
        end
    end
    if isempty(toProcess)
        return
    end

    % --no-compile only applies to editable local installs. Error if any
    % package in the batch is not an editable local install.
    if noCompile
        for i = 1:length(toProcess)
            p = toProcess{i};
            if ~(p.isLocal && p.editable)
                error('mip:update:noCompileRequiresEditable', ...
                      '--no-compile can only be used when all updated packages are editable local installs (offending package: "%s").', ...
                      mip.parse.display_fqn(p.fqn));
            end
        end
    end

    % Handle self-update (`gh/mip-org/core/mip`) separately and remove it
    % from the batch. mip cannot be uninstalled through the normal flow.
    keepMask = true(1, length(toProcess));
    for i = 1:length(toProcess)
        if strcmp(toProcess{i}.fqn, 'gh/mip-org/core/mip')
            updateSelf(toProcess{i}, force);
            keepMask(i) = false;
        end
    end
    toProcess = toProcess(keepMask);
    if isempty(toProcess)
        return
    end

    % Determine which of the remaining packages actually need updating.
    % For remote packages, also fetch the latest channel info (needed for
    % downloading the new version).
    needsUpdate = false(1, length(toProcess));
    for i = 1:length(toProcess)
        p = toProcess{i};
        if p.isLocal
            % Local packages are always reinstalled from source.
            needsUpdate(i) = true;
        else
            [needsUpdate(i), latestInfo] = checkRemoteNeedsUpdate(p, force);
            toProcess{i}.latestInfo = latestInfo;
        end
    end
    toProcess = toProcess(needsUpdate);

    if isempty(toProcess)
        return
    end

    % Split into local and remote sets
    localPkgs = {};
    remotePkgs = {};
    for i = 1:length(toProcess)
        if toProcess{i}.isLocal
            localPkgs{end+1} = toProcess{i}; %#ok<AGROW>
        else
            remotePkgs{end+1} = toProcess{i}; %#ok<AGROW>
        end
    end

    % Snapshot currently-loaded state so we can restore it after the
    % update cycle.
    loadedBefore = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    directlyLoadedBefore = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');

    % Wrap the update loops in try-catch so that reloadPreviouslyLoaded
    % always runs. Without this, a failure mid-batch would leave
    % already-updated packages unloaded for the rest of the session.
    updateError = [];
    try
        % --- Local packages: backup + install_local (no mip.uninstall) ---
        % Local packages cannot go through mip.uninstall because that prunes
        % orphaned deps, and install_local cannot re-fetch them from a channel.
        % The old package is moved to a backup directory before reinstalling so
        % that a failure in install_local does not destroy the installed copy.
        for i = 1:length(localPkgs)
            p = localPkgs{i};
            displayFqn = mip.parse.display_fqn(p.fqn);
            fprintf('Updating local package "%s"...\n', displayFqn);

            if mip.state.is_loaded(p.fqn)
                fprintf('Unloading "%s" before update...\n', displayFqn);
                mip.unload(p.fqn);
            end

            % Move old package to backup before reinstalling
            backupDir = [tempname '_mip_backup'];
            movefile(p.pkgDir, backupDir);
            mip.state.remove_directly_installed(p.fqn);
            packagesDir = mip.paths.get_packages_dir();
            mip.paths.cleanup_empty_dirs(fullfile(packagesDir, p.type));

            fprintf('Reinstalling "%s" from %s...\n', displayFqn, p.sourcePath);
            try
                mip.build.install_local(p.sourcePath, p.editable, noCompile, p.type);
            catch ME
                % Restore old package on failure
                parentDir = fileparts(p.pkgDir);
                if ~exist(parentDir, 'dir')
                    mkdir(parentDir);
                end
                movefile(backupDir, p.pkgDir);
                mip.state.add_directly_installed(p.fqn);
                rethrow(ME);
            end
            if exist(backupDir, 'dir')
                rmdir(backupDir, 's');
            end

            % Unpin if this was a forced update of a pinned package
            if force && mip.state.is_pinned(p.fqn)
                mip.state.remove_pinned(p.fqn);
                fprintf('Unpinned "%s".\n', displayFqn);
            end
        end

        % --- Remote packages: update via staging, install missing deps, prune ---
        % Each package is replaced on disk with the latest version from the
        % channel. Existing dependencies are left alone. After all packages are
        % updated, any missing dependencies are installed and orphaned packages
        % are pruned.
        if ~isempty(remotePkgs)
            for i = 1:length(remotePkgs)
                p = remotePkgs{i};
                displayFqn = mip.parse.display_fqn(p.fqn);
                if mip.state.is_loaded(p.fqn)
                    fprintf('Unloading "%s" before update...\n', displayFqn);
                    mip.unload(p.fqn);
                end
                downloadAndReplace(p);

                % Unpin if this was a forced update of a pinned package
                if force && mip.state.is_pinned(p.fqn)
                    mip.state.remove_pinned(p.fqn);
                    fprintf('Unpinned "%s".\n', displayFqn);
                end
            end

            % Install any missing dependencies that the updated packages require
            remoteFqns = cellfun(@(p) p.fqn, remotePkgs, 'UniformOutput', false);
            installMissingDeps(remoteFqns);

            % Prune packages that are no longer needed
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
        pkgInfo = struct('version', 'unknown', 'name', r.name);
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
        'org', r.org, ...
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
    channelStr = [p.org '/' p.channel];

    fprintf('Checking for updates to "%s" (installed: %s, channel: %s)...\n', ...
            displayFqn, installedVersion, channelStr);

    index = mip.channel.fetch_index(channelStr);

    % If the installed version is non-numeric (e.g. 'main', 'master',
    % 'unspecified'), pin the update lookup to that branch or version.
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
            index, p.org, p.channel, requestedVersions);
    catch err
        if strcmp(err.identifier, 'mip:versionNotFound')
            error('mip:update:versionNotInChannel', ...
                  ['Installed version "%s" of "%s" no longer exists in channel "%s". ' ...
                   'To switch to a different branch or version, run: mip install %s@<version>'], ...
                  installedVersion, fqn, channelStr, fqn);
        end
        rethrow(err);
    end

    currentArch = mip.arch();
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

function downloadAndReplace(p)
% Download the new version to a staging directory, then swap it in.
% The old package is moved to a backup and restored if the swap fails,
% so a failure at any point does not destroy the installed copy.

    displayFqn = mip.parse.display_fqn(p.fqn);
    fprintf('Downloading %s %s...\n', displayFqn, p.latestInfo.version);

    tempDir = tempname;
    mkdir(tempDir);
    try
        expectedSha = '';
        if isfield(p.latestInfo, 'mhl_sha256')
            expectedSha = p.latestInfo.mhl_sha256;
        end
        mhlPath = mip.channel.download_mhl(p.latestInfo.mhl_url, tempDir, expectedSha);
        stagingDir = fullfile(tempDir, 'staging');
        mip.channel.extract_mhl(mhlPath, stagingDir);

        % Download succeeded — swap old package out and new one in
        backupDir = [tempname '_mip_backup'];
        movefile(p.pkgDir, backupDir);
        try
            movefile(stagingDir, p.pkgDir);
        catch ME
            movefile(backupDir, p.pkgDir);
            rethrow(ME);
        end
        rmdir(backupDir, 's');
        fprintf('Successfully updated "%s" to %s\n', displayFqn, p.latestInfo.version);
    catch ME
        if exist(tempDir, 'dir')
            rmdir(tempDir, 's');
        end
        rethrow(ME);
    end
    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
    end
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
        for j = 1:length(deps)
            depFqn = mip.resolve.resolve_dependency(deps{j});
            depDir = mip.paths.get_package_dir(depFqn);
            if ~exist(depDir, 'dir')
                missingDeps{end+1} = deps{j}; %#ok<AGROW>
            end
        end
    end
    missingDeps = unique(missingDeps, 'stable');

    if isempty(missingDeps)
        return
    end

    fprintf('\nInstalling missing dependencies: %s\n', strjoin(missingDeps, ', '));

    % Record which packages are directly installed before calling mip.install
    % so we can undo any additions (missing deps should not be directly
    % installed).
    directBefore = mip.state.get_directly_installed();

    mip.install(missingDeps{:});

    directAfter = mip.state.get_directly_installed();
    newlyDirect = setdiff(directAfter, directBefore);
    for i = 1:length(newlyDirect)
        mip.state.remove_directly_installed(newlyDirect{i});
    end
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

    fqn = p.fqn;
    pkgDir = p.pkgDir;
    pkgInfo = p.pkgInfo;

    installedVersion = pkgInfo.version;
    channelStr = 'mip-org/core';

    fprintf('Checking for updates to mip (installed: %s)...\n', installedVersion);

    index = mip.channel.fetch_index(channelStr);
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    if ~isempty(installedVersion) && ~mip.resolve.is_numeric_version(installedVersion)
        requestedVersions(p.name) = installedVersion;
    end
    try
        [packageInfoMap, ~] = mip.resolve.build_package_info_map( ...
            index, 'mip-org', 'core', requestedVersions);
    catch err
        if strcmp(err.identifier, 'mip:versionNotFound')
            error('mip:update:versionNotInChannel', ...
                  ['Installed mip version "%s" no longer exists in mip-org/core. ' ...
                   'To switch to a different branch or version, run: mip install mip@<version>'], ...
                  installedVersion);
        end
        rethrow(err);
    end

    if ~packageInfoMap.isKey(fqn)
        error('mip:update:notInIndex', 'mip not found in the mip-org/core channel index.');
    end

    latestInfo = packageInfoMap(fqn);

    if ~force && ~mip.state.check_needs_update(pkgInfo, latestInfo)
        fprintf('mip is already up to date (%s)\n', installedVersion);
        return
    end

    fprintf('Updating mip: %s -> %s\n', installedVersion, latestInfo.version);

    tempDir = tempname;
    mkdir(tempDir);

    try
        expectedSha = '';
        if isfield(latestInfo, 'mhl_sha256')
            expectedSha = latestInfo.mhl_sha256;
        end
        mhlPath = mip.channel.download_mhl(latestInfo.mhl_url, tempDir, expectedSha);
        stagingDir = fullfile(tempDir, 'staging');
        mip.channel.extract_mhl(mhlPath, stagingDir);

        % Resolve all path lists BEFORE touching the installed mip. Once
        % we rmpath+rmdir the old mip, the mip.* helpers are no longer
        % reachable, so everything we need from them must be computed now.
        oldPathsToRemove = {};
        if isfield(pkgInfo, 'paths')
            oldSrcDir = mip.paths.get_source_dir(pkgDir, pkgInfo);
            oldPathsToRemove = resolvePathList(oldSrcDir, pkgInfo.paths);
        end

        % New package info is read from staging. After movefile, the
        % staging layout ends up at pkgDir, so source paths resolve under
        % pkgDir/<name>/.
        newPkgInfo = mip.config.read_package_json(stagingDir);
        newPathsToAdd = {};
        if isfield(newPkgInfo, 'paths')
            newSrcDir = fullfile(pkgDir, newPkgInfo.name);
            newPathsToAdd = resolvePathList(newSrcDir, newPkgInfo.paths);
        end

        % Unload the currently installed mip. Prefer the legacy
        % unload_package.m when present; otherwise rmpath the entries
        % declared in the old mip.json "paths" field.
        unloadScript = fullfile(pkgDir, 'unload_package.m');
        if exist(unloadScript, 'file')
            run(unloadScript);
        else
            oldWarn = warning('off', 'MATLAB:rmpath:DirNotFound');
            for k = 1:length(oldPathsToRemove)
                rmpath(oldPathsToRemove{k});
            end
            warning(oldWarn);
        end
        rmdir(pkgDir, 's');
        movefile(stagingDir, pkgDir);

        % Reload mip: addpath new entries (these now point into the
        % just-moved pkgDir), then run legacy load_package.m if present.
        for k = 1:length(newPathsToAdd)
            addpath(newPathsToAdd{k});
        end
        loadScript = fullfile(pkgDir, 'load_package.m');
        if exist(loadScript, 'file')
            run(loadScript);
        end
        fprintf('Successfully updated mip to %s\n', latestInfo.version);
    catch ME
        if exist(tempDir, 'dir')
            rmdir(tempDir, 's');
        end
        rethrow(ME);
    end

    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
    end
    fprintf('\nmip has been updated to %s.\n', latestInfo.version);
end

function out = resolvePathList(srcDir, relPaths)
% Resolve each entry in relPaths (relative to srcDir) to an absolute path.
    out = cell(1, length(relPaths));
    for i = 1:length(relPaths)
        if strcmp(relPaths{i}, '.')
            out{i} = srcDir;
        else
            out{i} = fullfile(srcDir, relPaths{i});
        end
    end
end

function expanded = expandWithDeps(args)
% Expand a list of package arguments to include their installed
% dependencies (recursively). The original packages come first, followed
% by any dependencies not already in the list.

    expanded = args;
    for i = 1:length(args)
        r = mip.resolve.resolve_to_installed(args{i});
        if isempty(r)
            % Not installed — will error later in resolvePackage; skip here
            continue
        end
        deps = mip.dependency.find_all_dependencies(r.fqn);
        for j = 1:length(deps)
            if mip.state.is_installed(deps{j}) && ~any(strcmp(expanded, deps{j}))
                expanded{end+1} = deps{j}; %#ok<AGROW>
            end
        end
    end
end
