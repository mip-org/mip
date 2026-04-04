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
% For remote packages, checks whether the installed version (and commit
% hash) matches the latest in the channel index. If already up to date,
% does nothing (unless --force is used).
%
% For local packages (installed from a local directory), always reinstalls
% from the original source directory.
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

    for i = 1:length(args)
        updateSinglePackage(args{i}, force);
    end
end

function updateSinglePackage(packageArg, force)

    % Resolve the package to its FQN
    result = mip.utils.parse_package_arg(packageArg);

    if result.is_fqn
        org = result.org;
        channelName = result.channel;
        packageName = result.name;
        fqn = packageArg;
    else
        % Bare name: find it among installed packages
        fqn = mip.utils.resolve_bare_name(result.name);
        if isempty(fqn)
            error('mip:update:notInstalled', ...
                  'Package "%s" is not installed. Run "mip install %s" first.', ...
                  result.name, result.name);
        end
        r = mip.utils.parse_package_arg(fqn);
        org = r.org;
        channelName = r.channel;
        packageName = r.name;
    end

    pkgDir = mip.utils.get_package_dir(org, channelName, packageName);

    % Check if package is installed
    if ~exist(pkgDir, 'dir')
        error('mip:update:notInstalled', ...
              'Package "%s" is not installed. Run "mip install %s" first.', ...
              fqn, fqn);
    end

    % Read installed package info
    try
        pkgInfo = mip.utils.read_package_json(pkgDir);
    catch
        pkgInfo = struct('version', 'unknown', 'name', packageName);
    end

    % Determine if this is a local package
    isLocal = strcmp(org, 'local') && strcmp(channelName, 'local');

    % Self-update: keep special handling (cannot uninstall mip)
    if strcmp(fqn, 'mip-org/core/mip')
        updateSelf(fqn, pkgDir, pkgInfo, force);
        return
    end

    if isLocal
        updateLocalPackage(fqn, pkgDir, pkgInfo);
    else
        updateRemotePackage(fqn, org, channelName, packageName, pkgDir, pkgInfo, force);
    end
end

function updateRemotePackage(fqn, org, channelName, packageName, pkgDir, pkgInfo, force)
    installedVersion = pkgInfo.version;
    channelStr = [org '/' channelName];

    fprintf('Checking for updates to "%s" (installed: %s, channel: %s)...\n', ...
            fqn, installedVersion, channelStr);

    % Fetch the index
    index = mip.utils.fetch_index(channelStr);
    [packageInfoMap, unavailablePackages] = mip.utils.build_package_info_map(index, org, channelName);

    % Find the package in the index
    currentArch = mip.arch();
    if ~packageInfoMap.isKey(fqn)
        if unavailablePackages.isKey(fqn)
            archs = unavailablePackages(fqn);
            error('mip:update:unavailable', ...
                  'Package "%s" is not available for architecture "%s". Available: %s', ...
                  packageName, currentArch, strjoin(archs, ', '));
        else
            error('mip:update:notInIndex', ...
                  'Package "%s" not found in the %s channel index.', ...
                  packageName, channelStr);
        end
    end

    latestInfo = packageInfoMap(fqn);
    latestVersion = latestInfo.version;

    % Check if up to date (version + commit hash)
    if ~force
        if strcmp(installedVersion, latestVersion)
            installedHash = '';
            if isfield(pkgInfo, 'commit_hash')
                installedHash = pkgInfo.commit_hash;
            end
            latestHash = '';
            if isfield(latestInfo, 'commit_hash')
                latestHash = latestInfo.commit_hash;
            end

            if isempty(latestHash) || strcmp(installedHash, latestHash)
                fprintf('Package "%s" is already up to date (%s)\n', fqn, installedVersion);
                return
            end

            fprintf('Version is "%s" but commit hash has changed (%s -> %s)\n', ...
                    installedVersion, installedHash, latestHash);
        end
    else
        fprintf('Force updating "%s" (%s)\n', fqn, installedVersion);
    end

    fprintf('Updating "%s": %s -> %s\n', fqn, installedVersion, latestVersion);

    % Note if loaded, then unload
    wasLoaded = mip.utils.is_loaded(fqn);
    if wasLoaded
        fprintf('Unloading "%s" before update...\n', fqn);
        mip.unload(fqn);
    end

    % Remove old package
    rmdir(pkgDir, 's');
    mip.utils.remove_directly_installed(fqn);
    cleanupEmptyDirs(fullfile(mip.utils.get_packages_dir(), org, channelName));
    cleanupEmptyDirs(fullfile(mip.utils.get_packages_dir(), org));

    % Install fresh
    fprintf('Reinstalling "%s"...\n', fqn);
    mip.install(fqn);

    % Reload if was loaded
    if wasLoaded
        fprintf('Reloading "%s"...\n', fqn);
        mip.load(fqn);
    end
end

function updateLocalPackage(fqn, pkgDir, pkgInfo)
    % Local packages always reinstall from source
    fprintf('Updating local package "%s"...\n', fqn);

    % Get source path and editable flag from mip.json
    if ~isfield(pkgInfo, 'source_path')
        error('mip:update:noSourcePath', ...
              'Local package "%s" does not have a source_path in mip.json. Cannot update.', fqn);
    end
    sourcePath = pkgInfo.source_path;
    isEditable = isfield(pkgInfo, 'editable') && pkgInfo.editable;

    % Check source directory still exists
    if ~isfolder(sourcePath)
        error('mip:update:sourceNotFound', ...
              'Source directory "%s" for package "%s" no longer exists.', sourcePath, fqn);
    end

    % Note if loaded, then unload
    wasLoaded = mip.utils.is_loaded(fqn);
    if wasLoaded
        fprintf('Unloading "%s" before update...\n', fqn);
        mip.unload(fqn);
    end

    % Remove old package
    rmdir(pkgDir, 's');
    mip.utils.remove_directly_installed(fqn);
    packagesDir = mip.utils.get_packages_dir();
    cleanupEmptyDirs(fullfile(packagesDir, 'local', 'local'));
    cleanupEmptyDirs(fullfile(packagesDir, 'local'));

    % Reinstall from source
    mip.utils.install_local(sourcePath, isEditable);

    % Reload if was loaded
    if wasLoaded
        fprintf('Reloading "%s"...\n', fqn);
        mip.load(fqn);
    end
end

function updateSelf(fqn, pkgDir, pkgInfo, force)
    % Self-update for mip-org/core/mip
    % Special handling: download and swap in place, then reload.
    installedVersion = pkgInfo.version;
    channelStr = 'mip-org/core';

    fprintf('Checking for updates to mip (installed: %s)...\n', installedVersion);

    index = mip.utils.fetch_index(channelStr);
    [packageInfoMap, ~] = mip.utils.build_package_info_map(index, 'mip-org', 'core');

    if ~packageInfoMap.isKey(fqn)
        error('mip:update:notInIndex', 'mip not found in the mip-org/core channel index.');
    end

    latestInfo = packageInfoMap(fqn);
    latestVersion = latestInfo.version;

    % Check if up to date
    if ~force
        if strcmp(installedVersion, latestVersion)
            installedHash = '';
            if isfield(pkgInfo, 'commit_hash')
                installedHash = pkgInfo.commit_hash;
            end
            latestHash = '';
            if isfield(latestInfo, 'commit_hash')
                latestHash = latestInfo.commit_hash;
            end

            if isempty(latestHash) || strcmp(installedHash, latestHash)
                fprintf('mip is already up to date (%s)\n', installedVersion);
                return
            end
        end
    end

    fprintf('Updating mip: %s -> %s\n', installedVersion, latestVersion);

    tempDir = tempname;
    mkdir(tempDir);

    try
        mhlPath = mip.utils.download_mhl(latestInfo.mhl_url, tempDir);
        stagingDir = fullfile(tempDir, 'staging');
        mip.utils.extract_mhl(mhlPath, stagingDir);
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

function cleanupEmptyDirs(dirPath)
    if ~exist(dirPath, 'dir')
        return
    end
    contents = dir(dirPath);
    contents = contents(~ismember({contents.name}, {'.', '..'}));
    if isempty(contents)
        rmdir(dirPath);
    end
end
