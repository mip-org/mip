function info(varargin)
%INFO   Display detailed information about a package.
%
% Usage:
%   mip.info('packageName')
%   mip.info('org/channel/packageName')
%   mip.info('--channel', 'dev', 'packageName')
%   mip.info('--channel', 'owner/chan', 'packageName')
%
% Options:
%   --channel <name>  Query a specific channel (default: mip-org/core)
%
% Displays detailed information about a package from the repository,
% including all available versions, installation status, loaded status,
% dependencies.

if nargin < 1
    error('mip:noPackage', 'Package name is required');
end

[channel, args] = mip.utils.parse_channel_flag(varargin);

if isempty(args)
    error('mip:noPackage', 'Package name is required');
end

packageArg = args{1};
if isstring(packageArg)
    packageArg = char(packageArg);
end

% Determine channel from FQN or flag
if isempty(channel)
    channel = 'mip-org/core';
end

[org, channelName, packageName] = mip.utils.resolve_package_name(packageArg, channel);
fqn = mip.utils.make_fqn(org, channelName, packageName);

% Reconstruct channel string for index lookup
if strcmp(org, 'mip-org')
    channelStr = channelName;
else
    channelStr = [org '/' channelName];
end

try
    indexUrl = mip.index(channelStr);
    fprintf('Using channel: %s/%s\n', org, channelName);
    tempFile = [tempname, '.json'];
    websave(tempFile, indexUrl);
    indexJson = fileread(tempFile);
    delete(tempFile);

    index = jsondecode(indexJson);

    % Get current architecture
    currentArch = mip.arch();

    % Find all variants of this package in the repository
    packages = index.packages;
    packageVariants = {};

    for i = 1:length(packages)
        if iscell(packages)
            pkg = packages{i};
        else
            pkg = packages(i);
        end

        if isstruct(pkg) && strcmp(pkg.name, packageName)
            packageVariants = [packageVariants, {pkg}]; %#ok<*AGROW>
        end
    end

    if isempty(packageVariants)
        error('mip:packageNotFound', ...
              'Package "%s" not found in repository', packageName);
    end

    % Group variants by version
    versionMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:length(packageVariants)
        variant = packageVariants{i};
        version = variant.version;
        if ~versionMap.isKey(version)
            versionMap(version) = {};
        end
        variants = versionMap(version);
        versionMap(version) = [variants, {variant}];
    end

    % Get all versions (sorted by version number)
    allVersions = keys(versionMap);
    allVersions = sortVersions(allVersions);

    % Find compatible variant for current architecture (latest version)
    latestVersion = allVersions{end};
    latestVariants = versionMap(latestVersion);
    compatibleVariant = [];

    canFallbackToWasm = startsWith(currentArch, 'numbl_') && ~strcmp(currentArch, 'numbl_wasm');
    for i = 1:length(latestVariants)
        v = latestVariants{i};
        arch = v.architecture;
        if strcmp(arch, currentArch) || strcmp(arch, 'any')
            compatibleVariant = v;
            break;
        end
    end
    if isempty(compatibleVariant) && canFallbackToWasm
        for i = 1:length(latestVariants)
            v = latestVariants{i};
            if strcmp(v.architecture, 'numbl_wasm')
                compatibleVariant = v;
                break;
            end
        end
    end

    % Check if package is installed (namespaced directory)
    pkgDir = mip.utils.get_package_dir(org, channelName, packageName);
    isInstalled = exist(pkgDir, 'dir');

    installedVersion = '';
    installedInfo = [];
    if isInstalled
        installedInfo = mip.utils.read_package_json(pkgDir);
        if isfield(installedInfo, 'version')
            installedVersion = installedInfo.version;
        end
    end

    % Check if package is loaded
    isLoaded = mip.utils.is_loaded(fqn);
    isSticky = mip.utils.is_sticky(fqn);

    % Display package information
    fprintf('\n');
    fprintf('=== Package Information ===\n\n');
    fprintf('Name: %s\n', fqn);

    % Show available versions
    fprintf('\nAvailable Versions:\n');
    for i = 1:length(allVersions)
        version = allVersions{i};
        variants = versionMap(version);

        archs = {};
        for j = 1:length(variants)
            archs = [archs, {variants{j}.architecture}];
        end

        fprintf('  - %s (%s)\n', version, strjoin(archs, ', '));
    end

    % Show installation status
    fprintf('\n');
    if isInstalled
        fprintf('Installed: Yes (version %s)\n', installedVersion);
        fprintf('Installation Path: %s\n', pkgDir);
    else
        fprintf('Installed: No\n');
    end

    % Show loaded status
    if isLoaded
        if isSticky
            fprintf('Loaded: Yes (sticky)\n');
        else
            fprintf('Loaded: Yes\n');
        end
    else
        fprintf('Loaded: No\n');
    end

    % Show dependencies
    fprintf('\n');
    if isInstalled && isfield(installedInfo, 'dependencies') && ~isempty(installedInfo.dependencies)
        fprintf('Dependencies (installed version):\n');
        deps = installedInfo.dependencies;
        if ~iscell(deps)
            deps = {deps};
        end
        for i = 1:length(deps)
            fprintf('  - %s\n', deps{i});
        end
    elseif ~isempty(compatibleVariant) && isfield(compatibleVariant, 'dependencies') && ~isempty(compatibleVariant.dependencies)
        fprintf('Dependencies (latest version):\n');
        deps = compatibleVariant.dependencies;
        if ~iscell(deps)
            deps = {deps};
        end
        for i = 1:length(deps)
            fprintf('  - %s\n', deps{i});
        end
    else
        fprintf('Dependencies: None\n');
    end

    fprintf('\n');

catch ME
    if strcmp(ME.identifier, 'mip:packageNotFound')
        rethrow(ME);
    else
        error('mip:infoFailed', ...
              'Failed to retrieve package information: %s', ME.message);
    end
end

end

function sorted = sortVersions(versions)
    n = length(versions);
    sorted = versions;
    for i = 2:n
        key = sorted{i};
        j = i - 1;
        while j >= 1 && mip.utils.compare_versions(sorted{j}, key) > 0
            sorted{j+1} = sorted{j};
            j = j - 1;
        end
        sorted{j+1} = key;
    end
end
