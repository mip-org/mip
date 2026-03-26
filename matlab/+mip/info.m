function info(varargin)
%INFO   Display detailed information about a package.
%
% Usage:
%   mip.info('packageName')
%   mip.info('--channel', 'dev', 'packageName')
%
% Options:
%   --channel <name>  Query a specific channel (default: core)
%
% Displays detailed information about a package from the repository,
% including all available versions, installation status, loaded status,
% dependencies, and exposed symbols (if installed).
%
% Example:
%   mip.info('chebfun')

if nargin < 1
    error('mip:noPackage', 'Package name is required');
end

[channel, args] = mip.utils.parse_channel_flag(varargin);

if isempty(args)
    error('mip:noPackage', 'Package name is required');
end

packageName = args{1};
if isstring(packageName)
    packageName = char(packageName);
end

try
    % Download and parse package index
    indexUrl = mip.index(channel);
    if ~isempty(channel)
        fprintf('Using channel: %s\n', channel);
    end
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
        % Handle both cell arrays and struct arrays
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
    
    for i = 1:length(latestVariants)
        v = latestVariants{i};
        arch = v.architecture;
        if strcmp(arch, currentArch) || strcmp(arch, 'any')
            compatibleVariant = v;
            break;
        end
    end
    
    % Check if package is installed
    packagesDir = mip.utils.get_packages_dir();
    pkgDir = fullfile(packagesDir, packageName);
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
    isLoaded = mip.utils.is_loaded(packageName);
    isSticky = mip.utils.is_sticky(packageName);
    
    % Display package information
    fprintf('\n');
    fprintf('=== Package Information ===\n\n');
    fprintf('Name: %s\n', packageName);
    
    % Show available versions
    fprintf('\nAvailable Versions:\n');
    for i = 1:length(allVersions)
        version = allVersions{i};
        variants = versionMap(version);
        
        % Get architectures for this version
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
        installedChannel = mip.utils.get_package_channel(packageName);
        if ~isempty(installedChannel)
            fprintf('Channel: %s\n', installedChannel);
        end
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
    % If installed, show dependencies of installed version
    % Otherwise, show dependencies of latest version
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
    
    % Show exposed symbols only if installed
    if isInstalled
        if isfield(installedInfo, 'exposed_symbols') && ~isempty(installedInfo.exposed_symbols)
            symbols = installedInfo.exposed_symbols;
            if ~iscell(symbols)
                symbols = {symbols};
            end
            fprintf('\nExposed Symbols (%d):\n', length(symbols));
            for i = 1:min(10, length(symbols))
                fprintf('  - %s\n', symbols{i});
            end
            if length(symbols) > 10
                fprintf('  ... and %d more\n', length(symbols) - 10);
            end
        else
            fprintf('\nExposed Symbols: None listed\n');
        end
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
% Sort version strings by version number (ascending)
    n = length(versions);
    sorted = versions;
    % Simple insertion sort using compare_versions
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
