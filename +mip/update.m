function update(varargin)
%UPDATE   Update one or more installed mip packages.
%
% Usage:
%   mip.update('packageName')
%   mip.update('org/channel/packageName')
%   mip.update('package1', 'package2')
%   mip.update('--force', 'packageName')
%   mip.update('mip')
%
% Options:
%   --force           Force update even if already up to date
%
% For each requested package, checks whether an update is needed. For
% remote packages, the installed version (and commit hash) is compared
% against the latest in the channel index. Local packages are always
% considered to need an update. If a package does not need updating,
% nothing happens for that package (unless --force is specified).
%
% Remote packages are updated in place: the old directory is removed and
% the new version is downloaded. Existing dependencies are not updated.
% After the update, any new dependencies that the updated package requires
% are installed, and any orphaned packages (old dependencies no longer
% needed by any directly installed package) are pruned.
%
% Local packages are reinstalled directly from their source path without
% going through uninstall (since install_local cannot re-fetch deps from
% a channel).
%
% Any packages that were loaded before the update are reloaded afterward.
%
% Accepts both bare package names and fully qualified names.

    if nargin < 1
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    % Check for --force flag
    force = false;
    args = {};
    for i = 1:length(varargin)
        arg = varargin{i};
        if ischar(arg) && strcmp(arg, '--force')
            force = true;
        else
            args{end+1} = arg; %#ok<AGROW>
        end
    end

    if isempty(args)
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    % Resolve and validate each argument. Any error here (not installed,
    % missing source_path, missing source dir) is raised before we touch
    % anything on disk.
    toProcess = cell(1, length(args));
    for i = 1:length(args)
        toProcess{i} = resolvePackage(args{i});
    end

    % Handle self-update (`mip-org/core/mip`) separately and remove it
    % from the batch. mip cannot be uninstalled through the normal flow.
    keepMask = true(1, length(toProcess));
    for i = 1:length(toProcess)
        if strcmp(toProcess{i}.fqn, 'mip-org/core/mip')
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

    % --- Local packages: rmdir + install_local (no mip.uninstall) ---
    % Local packages cannot go through mip.uninstall because that prunes
    % orphaned deps, and install_local cannot re-fetch them from a channel.
    for i = 1:length(localPkgs)
        p = localPkgs{i};
        fprintf('Updating local package "%s"...\n', p.fqn);

        if mip.state.is_loaded(p.fqn)
            fprintf('Unloading "%s" before update...\n', p.fqn);
            mip.unload(p.fqn);
        end

        rmdir(p.pkgDir, 's');
        mip.state.remove_directly_installed(p.fqn);
        packagesDir = mip.paths.get_packages_dir();
        mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'local', 'local'));
        mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'local'));

        fprintf('Reinstalling "%s" from %s...\n', p.fqn, p.sourcePath);
        mip.build.install_local(p.sourcePath, p.editable);
    end

    % --- Remote packages: update in place, install new deps, prune ---
    % Each package is replaced on disk with the latest version from the
    % channel. Existing dependencies are left alone. After all packages are
    % updated, any new dependencies are installed and orphaned packages are
    % pruned.
    if ~isempty(remotePkgs)
        for i = 1:length(remotePkgs)
            p = remotePkgs{i};
            if mip.state.is_loaded(p.fqn)
                fprintf('Unloading "%s" before update...\n', p.fqn);
                mip.unload(p.fqn);
            end
            downloadAndReplace(p);
        end

        % Install any new dependencies that the updated packages require
        remoteFqns = cellfun(@(p) p.fqn, remotePkgs, 'UniformOutput', false);
        installMissingDeps(remoteFqns);

        % Prune packages that are no longer needed
        mip.state.prune_unused_packages();
    end

    % Reload anything that was loaded before update but isn't now.
    reloadPreviouslyLoaded(loadedBefore, directlyLoadedBefore);
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

    isLocal = strcmp(r.org, 'local') && strcmp(r.channel, 'local');
    sourcePath = '';
    editable = false;
    if isLocal
        if ~isfield(pkgInfo, 'source_path')
            error('mip:update:noSourcePath', ...
                  'Local package "%s" does not have a source_path in mip.json. Cannot update.', r.fqn);
        end
        sourcePath = pkgInfo.source_path;
        if ~isfolder(sourcePath)
            error('mip:update:sourceNotFound', ...
                  'Source directory "%s" for package "%s" no longer exists.', sourcePath, r.fqn);
        end
        editable = isfield(pkgInfo, 'editable') && pkgInfo.editable;
    end

    p = struct( ...
        'fqn', r.fqn, ...
        'org', r.org, ...
        'channel', r.channel, ...
        'name', r.name, ...
        'pkgDir', r.pkg_dir, ...
        'pkgInfo', pkgInfo, ...
        'isLocal', isLocal, ...
        'sourcePath', sourcePath, ...
        'editable', editable ...
    );
end

function [tf, latestInfo] = checkRemoteNeedsUpdate(p, force)
% Fetch the channel index and decide whether p needs updating.
% Also returns the latestInfo struct (needed for downloading).

    fqn = p.fqn;
    installedVersion = p.pkgInfo.version;
    channelStr = [p.org '/' p.channel];

    fprintf('Checking for updates to "%s" (installed: %s, channel: %s)...\n', ...
            fqn, installedVersion, channelStr);

    index = mip.channel.fetch_index(channelStr);
    [packageInfoMap, unavailablePackages] = mip.resolve.build_package_info_map(index, p.org, p.channel);

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
        fprintf('Force updating "%s" (%s)\n', fqn, installedVersion);
        tf = true;
        return
    end

    if ~mip.state.check_needs_update(p.pkgInfo, latestInfo)
        fprintf('Package "%s" is already up to date (%s)\n', fqn, installedVersion);
        tf = false;
        return
    end

    fprintf('Updating "%s": %s -> %s\n', fqn, installedVersion, latestInfo.version);
    tf = true;
end

function downloadAndReplace(p)
% Remove the old package directory and download the new version.

    fprintf('Downloading %s %s...\n', p.fqn, p.latestInfo.version);

    rmdir(p.pkgDir, 's');

    tempDir = tempname;
    mkdir(tempDir);
    try
        mhlPath = mip.channel.download_mhl(p.latestInfo.mhl_url, tempDir);
        parentDir = fileparts(p.pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end
        mip.channel.extract_mhl(mhlPath, p.pkgDir);
        fprintf('Successfully updated "%s" to %s\n', p.fqn, p.latestInfo.version);
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
        r = mip.parse.parse_package_arg(fqn);
        pkgDir = mip.paths.get_package_dir(r.org, r.channel, r.name);
        if ~exist(pkgDir, 'dir')
            continue
        end
        try
            pkgInfo = mip.config.read_package_json(pkgDir);
        catch
            continue
        end
        deps = pkgInfo.dependencies;
        if isempty(deps) || (isnumeric(deps) && isempty(deps))
            continue
        end
        if ~iscell(deps)
            deps = {deps};
        end
        for j = 1:length(deps)
            depFqn = mip.resolve.resolve_dependency(deps{j});
            depR = mip.parse.parse_package_arg(depFqn);
            depDir = mip.paths.get_package_dir(depR.org, depR.channel, depR.name);
            if ~exist(depDir, 'dir')
                missingDeps{end+1} = deps{j}; %#ok<AGROW>
            end
        end
    end
    missingDeps = unique(missingDeps, 'stable');

    if isempty(missingDeps)
        return
    end

    fprintf('\nInstalling new dependencies: %s\n', strjoin(missingDeps, ', '));

    % Record which packages are directly installed before calling mip.install
    % so we can undo any additions (new deps should not be directly installed).
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
        pkgDir = mip.paths.get_package_dir(r.org, r.channel, r.name);
        if ~exist(pkgDir, 'dir')
            fprintf('Warning: "%s" was loaded before update but is no longer installed; skipping reload.\n', pkg);
            continue
        end
        fprintf('Reloading "%s"...\n', pkg);
        if ismember(pkg, directlyLoadedBefore)
            mip.load(pkg);
        else
            mip.load(pkg, '--transitive');
        end
    end
end

function updateSelf(p, force)
% Self-update for mip-org/core/mip. mip cannot be uninstalled through
% the normal flow, so we download and swap in place.

    fqn = p.fqn;
    pkgDir = p.pkgDir;
    pkgInfo = p.pkgInfo;

    installedVersion = pkgInfo.version;
    channelStr = 'mip-org/core';

    fprintf('Checking for updates to mip (installed: %s)...\n', installedVersion);

    index = mip.channel.fetch_index(channelStr);
    [packageInfoMap, ~] = mip.resolve.build_package_info_map(index, 'mip-org', 'core');

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
        mhlPath = mip.channel.download_mhl(latestInfo.mhl_url, tempDir);
        stagingDir = fullfile(tempDir, 'staging');
        mip.channel.extract_mhl(mhlPath, stagingDir);
        rmdir(pkgDir, 's');
        movefile(stagingDir, pkgDir);
        fprintf('Successfully updated mip to %s\n', latestVersion);
    catch ME
        if exist(tempDir, 'dir')
            rmdir(tempDir, 's');
        end
        rethrow(ME);
    end

    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
    end

    % Reload mip
    loadScript = fullfile(pkgDir, 'load_package.m');
    if exist(loadScript, 'file')
        run(loadScript);
    end
    fprintf('\nmip has been updated to %s.\n', latestVersion);
end

