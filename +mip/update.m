function update(varargin)
%UPDATE   Update one or more installed mip packages.
%
% Usage:
%   mip.update('packageName')
%   mip.update('org/channel/packageName')
%   mip.update('package1', 'package2')
%   mip.update('--channel', 'dev', 'packageName')
%   mip.update('--force', 'packageName')
%   mip.update('mip')
%
% Options:
%   --channel <name>  Use a specific channel (overrides installed channel)
%   --force           Force update even if already up to date
%
% Accepts both bare package names and fully qualified names.

    if nargin < 1
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    % Check for --force flag
    force = false;
    filteredArgs = {};
    for i = 1:length(varargin)
        arg = varargin{i};
        if ischar(arg) && strcmp(arg, '--force')
            force = true;
        else
            filteredArgs{end+1} = arg;
        end
    end

    [channelOverride, args] = mip.utils.parse_channel_flag(filteredArgs);

    if isempty(args)
        error('mip:update:noPackage', 'At least one package name is required for update command.');
    end

    for i = 1:length(args)
        updateSinglePackage(args{i}, channelOverride, force);
    end
end

function updateSinglePackage(packageArg, channelOverride, force)

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
    [packageInfoMap, unavailablePackages] = mip.utils.build_package_info_map(index, fetchOrg, fetchChan);

    % Find the package in the index (use FQN for the fetch channel)
    currentArch = mip.arch();
    indexFqn = mip.utils.make_fqn(fetchOrg, fetchChan, packageName);
    if ~packageInfoMap.isKey(indexFqn)
        if unavailablePackages.isKey(indexFqn)
            archs = unavailablePackages(indexFqn);
            error('mip:update:unavailable', ...
                  'Package "%s" is not available for architecture "%s". Available: %s', ...
                  packageName, currentArch, strjoin(archs, ', '));
        else
            error('mip:update:notInIndex', ...
                  'Package "%s" not found in the %s/%s channel index.', ...
                  packageName, fetchOrg, fetchChan);
        end
    end

    latestInfo = packageInfoMap(indexFqn);
    latestVersion = latestInfo.version;

    % Compare versions and commit hashes
    if strcmp(installedVersion, latestVersion)
        % Versions match — check if commit hash has changed (e.g. branch tracking)
        installedHash = '';
        if isfield(pkgInfo, 'commit_hash')
            installedHash = pkgInfo.commit_hash;
        end
        latestHash = '';
        if isfield(latestInfo, 'commit_hash')
            latestHash = latestInfo.commit_hash;
        end

        if ~force && (isempty(latestHash) || strcmp(installedHash, latestHash))
            fprintf('Package "%s" is already up to date (%s)\n', fqn, installedVersion);
            return
        end

        if ~force
            fprintf('Version is "%s" but commit hash has changed (%s -> %s)\n', ...
                    installedVersion, installedHash, latestHash);
        else
            fprintf('Force updating "%s" (%s)\n', fqn, installedVersion);
        end
    end

    fprintf('Updating "%s": %s -> %s\n', fqn, installedVersion, latestVersion);

    % Check if the package is currently loaded
    wasLoaded = mip.utils.is_loaded(fqn);
    isSelfUpdate = strcmp(fqn, 'mip-org/core/mip');

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

    % Post-update: restore path for self-update
    if isSelfUpdate
        loadScript = fullfile(pkgDir, 'load_package.m');
        if exist(loadScript, 'file')
            run(loadScript);
        end
        fprintf('\nmip has been updated to %s.\n', latestVersion);
    elseif wasLoaded
        fprintf('Note: "%s" was loaded. Run "mip unload %s" and "mip load %s" to use the new version.\n', ...
                fqn, fqn, fqn);
    end
end
