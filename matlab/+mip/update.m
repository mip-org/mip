function update(varargin)
%UPDATE   Update one or more installed mip packages.
%
% Usage:
%   mip.update('packageName')
%   mip.update('org/channel/packageName')
%   mip.update('package1', 'package2')
%   mip.update('--channel', 'dev', 'packageName')
%   mip.update('mip')
%
% Options:
%   --channel <name>  Use a specific channel (overrides installed channel)
%
% Accepts both bare package names and fully qualified names.

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

function updateSinglePackage(packageArg, channelOverride)

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

    % Check if package is an editable install
    try
        pkgMeta = mip.utils.read_package_json(pkgDir);
        if isfield(pkgMeta, 'editable') && pkgMeta.editable
            fprintf('Package "%s" is an editable install (source: %s).\n', ...
                    fqn, pkgMeta.source_path);
            fprintf('Update the source directly (e.g., git pull) instead of using mip update.\n');
            return
        end
    catch
    end

    % Determine which channel to use for fetching updates
    if ~isempty(channelOverride)
        [fetchOrg, fetchChan] = mip.utils.parse_channel_spec(channelOverride);
        if strcmp(fetchOrg, 'mip-org')
            channelStr = fetchChan;
        else
            channelStr = [fetchOrg '/' fetchChan];
        end
    else
        % Use the channel encoded in the package path
        if strcmp(org, 'mip-org')
            channelStr = channelName;
        else
            channelStr = [org '/' channelName];
        end
        fetchOrg = org;
        fetchChan = channelName;
    end

    % Read installed version
    try
        pkgInfo = mip.utils.read_package_json(pkgDir);
        installedVersion = pkgInfo.version;
    catch
        installedVersion = 'unknown';
    end

    fprintf('Checking for updates to "%s" (installed: %s, channel: %s/%s)...\n', ...
            fqn, installedVersion, fetchOrg, fetchChan);

    % Fetch the index and build package info map
    index = mip.utils.fetch_index(channelStr);
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
                  'Package "%s" not found in the %s/%s channel index.', ...
                  packageName, fetchOrg, fetchChan);
        end
    end

    latestInfo = packageInfoMap(packageName);
    latestVersion = latestInfo.version;

    % Compare versions
    if strcmp(installedVersion, latestVersion)
        fprintf('Package "%s" is already up to date (%s)\n', fqn, installedVersion);
        return
    end

    fprintf('Updating "%s": %s -> %s\n', fqn, installedVersion, latestVersion);

    % Check if the package is currently loaded
    wasLoaded = mip.utils.is_loaded(fqn);
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
        rmdir(pkgDir, 's');
        movefile(stagingDir, pkgDir);

        fprintf('Successfully updated "%s" to %s\n', fqn, latestVersion);

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
                fqn, fqn, fqn);
    end
end
