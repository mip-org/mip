function update(varargin)
%UPDATE   Update one or more installed mip packages.
%
% Usage:
%   mip.update('packageName')
%   mip.update('package1', 'package2')
%   mip.update('--channel', 'dev', 'packageName')
%   mip.update('mip')
%
% Options:
%   --channel <name>  Use a specific channel (default: package's installed channel)
%
% This function checks the repository for a newer version of an installed
% package and replaces it if one is available. For 'mip update mip', it
% updates the mip package manager itself.

    if nargin < 1
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    [channelOverride, args] = mip.utils.parse_channel_flag(varargin);

    if isempty(args)
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    for i = 1:length(args)
        updateSinglePackage(args{i}, channelOverride);
    end
end

function updateSinglePackage(packageName, channelOverride)
    packagesDir = mip.utils.get_packages_dir();
    packageDir = fullfile(packagesDir, packageName);

    % Check if package is installed
    if ~exist(packageDir, 'dir')
        error('mip:update:notInstalled', ...
              'Package "%s" is not installed. Run "mip install %s" first.', ...
              packageName, packageName);
    end

    % Determine which channel to use
    if ~isempty(channelOverride)
        channel = channelOverride;
    else
        channel = mip.utils.get_package_channel(packageName);
        if isempty(channel)
            channel = 'core';
        end
    end

    % Read installed version
    try
        pkgInfo = mip.utils.read_package_json(packageDir);
        installedVersion = pkgInfo.version;
    catch
        installedVersion = 'unknown';
    end

    fprintf('Checking for updates to "%s" (installed: %s, channel: %s)...\n', ...
            packageName, installedVersion, channel);

    % Fetch the index and build package info map
    index = mip.utils.fetch_index(channel);
    [packageInfoMap, unavailablePackages] = mip.utils.build_package_info_map(index);

    % Find the package in the index
    currentArch = mip.arch();
    if ~packageInfoMap.isKey(packageName)
        if unavailablePackages.isKey(packageName)
            archs = unavailablePackages(packageName);
            error('mip:update:unavailable', ...
                  'Package "%s" is not available for architecture "%s". Available: %s', ...
                  packageName, currentArch, strjoin(archs, ', '));
        else
            error('mip:update:notInIndex', ...
                  'Package "%s" not found in the %s channel index.', ...
                  packageName, channel);
        end
    end

    latestInfo = packageInfoMap(packageName);
    latestVersion = latestInfo.version;

    % Compare versions
    if strcmp(installedVersion, latestVersion)
        fprintf('Package "%s" is already up to date (%s)\n', packageName, installedVersion);
        return
    end

    fprintf('Updating "%s": %s -> %s\n', packageName, installedVersion, latestVersion);

    % Check if the package is currently loaded
    wasLoaded = mip.utils.is_loaded(packageName);
    isSelfUpdate = strcmp(packageName, 'mip');

    % Download the new version
    tempDir = tempname;
    mkdir(tempDir);

    try
        mhlPath = mip.utils.download_mhl(latestInfo.mhl_url, tempDir);

        % Extract to a staging directory
        stagingDir = fullfile(tempDir, 'staging');
        mip.utils.extract_mhl(mhlPath, stagingDir);

        % Remove old package and move new one in
        rmdir(packageDir, 's');
        movefile(stagingDir, packageDir);

        fprintf('Successfully updated "%s" to %s\n', packageName, latestVersion);

        % Update channel tracking
        mip.utils.set_package_channel(packageName, channel);
    catch ME
        if exist(tempDir, 'dir')
            rmdir(tempDir, 's');
        end
        rethrow(ME);
    end

    % Clean up temp dir
    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
    end

    % Post-update messages
    if isSelfUpdate
        fprintf('\nmip has been updated to %s.\n', latestVersion);
    elseif wasLoaded
        fprintf('Note: "%s" was loaded. Run "mip unload %s" and "mip load %s" to use the new version.\n', ...
                packageName, packageName, packageName);
    end
end
