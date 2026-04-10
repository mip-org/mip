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
% Shows two kinds of information:
%   1. Local installation(s) — version, path, loaded/sticky status, deps
%   2. Remote channel info — available versions and architectures
%
% If the package is installed from a channel other than the one being
% queried, that channel's remote index is also fetched and displayed.

if nargin < 1
    error('mip:noPackage', 'Package name is required');
end

[channel, args] = mip.parse.parse_channel_flag(varargin);

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

[org, channelName, packageName] = mip.resolve.resolve_package_name(packageArg, channel);

% Find all local installations of this package
result = mip.parse.parse_package_arg(packageArg);
if result.is_fqn
    % FQN: only check that specific installation
    pkgDir = mip.paths.get_package_dir(org, channelName, packageName);
    if exist(pkgDir, 'dir')
        installedFqns = {mip.parse.make_fqn(org, channelName, packageName)};
    else
        installedFqns = {};
    end
else
    % Bare name: find all installations across channels
    installedFqns = mip.resolve.find_all_installed_by_name(packageName);
end

% ---- Collect channels to query ----

channelsToQuery = {[org '/' channelName]};
for i = 1:length(installedFqns)
    r = mip.parse.parse_package_arg(installedFqns{i});
    ch = [r.org '/' r.channel];
    % Skip local/local — no remote index for local installs
    if strcmp(ch, 'local/local')
        continue
    end
    if ~ismember(ch, channelsToQuery)
        channelsToQuery{end+1} = ch; %#ok<AGROW>
    end
end

% ---- Pre-fetch remote indexes ----

remoteIndexes = cell(size(channelsToQuery));
for i = 1:length(channelsToQuery)
    remoteIndexes{i} = fetchRemoteIndex(channelsToQuery{i});
end

% Check if package exists in any remote channel
foundRemote = false;
for i = 1:length(remoteIndexes)
    if ~isempty(remoteIndexes{i}) && packageInIndex(remoteIndexes{i}, packageName)
        foundRemote = true;
        break
    end
end

% If the package is not installed locally and not in any remote channel,
% error before printing anything.
if isempty(installedFqns) && ~foundRemote
    error('mip:unknownPackage', ...
        'Unknown package "%s" in channel "%s".', ...
        packageName, strjoin(channelsToQuery, '", "'));
end

% ---- Section 1: Local installation(s) ----

fprintf('\n');

if ~isempty(installedFqns)
    fprintf('=== Local Installation(s) ===\n');
    for i = 1:length(installedFqns)
        fqn = installedFqns{i};
        showLocalInstallInfo(fqn);
    end
else
    fprintf('=== Local Installation(s) ===\n');
    fprintf('\n  Not installed.\n\n');
end

% ---- Section 2: Remote channel info ----

for i = 1:length(channelsToQuery)
    showRemoteChannelInfo(channelsToQuery{i}, packageName, remoteIndexes{i});
end

end


function showLocalInstallInfo(fqn)
% Display info about a single local installation.

    r = mip.parse.parse_package_arg(fqn);
    pkgDir = mip.paths.get_package_dir(r.org, r.channel, r.name);

    fprintf('\n  %s\n', fqn);

    try
        pkgInfo = mip.config.read_package_json(pkgDir);
    catch
        fprintf('    (could not read mip.json)\n\n');
        return
    end

    if isfield(pkgInfo, 'version')
        fprintf('    Version: %s\n', pkgInfo.version);
    end

    fprintf('    Path: %s\n', pkgDir);

    % Loaded / sticky status
    isLoaded = mip.state.is_loaded(fqn);
    isSticky = mip.state.is_sticky(fqn);
    if isLoaded && isSticky
        fprintf('    Loaded: Yes (sticky)\n');
    elseif isLoaded
        fprintf('    Loaded: Yes\n');
    else
        fprintf('    Loaded: No\n');
    end

    % Editable
    if isfield(pkgInfo, 'editable') && pkgInfo.editable
        fprintf('    Editable: Yes\n');
        if isfield(pkgInfo, 'source_path')
            fprintf('    Source: %s\n', pkgInfo.source_path);
        end
    end

    % Dependencies
    if isfield(pkgInfo, 'dependencies') && ~isempty(pkgInfo.dependencies)
        deps = pkgInfo.dependencies;
        if ~iscell(deps)
            deps = {deps};
        end
        fprintf('    Dependencies: %s\n', strjoin(deps, ', '));
    else
        fprintf('    Dependencies: None\n');
    end

    fprintf('\n');
end


function index = fetchRemoteIndex(channelStr)
% Fetch the remote index for a channel. Returns [] on failure.
    try
        index = mip.channel.fetch_index(channelStr);
    catch
        index = [];
    end
end


function found = packageInIndex(index, packageName)
% Check if a package exists in a pre-fetched index.
    found = false;
    packages = index.packages;
    for i = 1:length(packages)
        if iscell(packages)
            pkg = packages{i};
        else
            pkg = packages(i);
        end
        if isstruct(pkg) && strcmp(pkg.name, packageName)
            found = true;
            return
        end
    end
end


function showRemoteChannelInfo(channelStr, packageName, index)
% Display remote channel info for a package using a pre-fetched index.

    [chOrg, chName] = mip.parse.parse_channel_spec(channelStr);

    fprintf('=== Remote Channel: %s/%s ===\n\n', chOrg, chName);

    if isempty(index)
        fprintf('  Could not fetch index.\n\n');
        return
    end

    % Find all variants of this package
    packages = index.packages;
    packageVariants = {};
    for i = 1:length(packages)
        if iscell(packages)
            pkg = packages{i};
        else
            pkg = packages(i);
        end
        if isstruct(pkg) && strcmp(pkg.name, packageName)
            packageVariants = [packageVariants, {pkg}]; %#ok<AGROW>
        end
    end

    if isempty(packageVariants)
        fprintf('  Package "%s" not found in this channel.\n\n', packageName);
        return
    end

    % Group by version
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

    allVersions = sortVersions(keys(versionMap));

    fprintf('  Available Versions:\n');
    for i = 1:length(allVersions)
        version = allVersions{i};
        variants = versionMap(version);
        archs = {};
        for j = 1:length(variants)
            archs = [archs, {variants{j}.architecture}]; %#ok<AGROW>
        end
        fprintf('    - %s (%s)\n', version, strjoin(archs, ', '));
    end

    % Show dependencies from latest compatible variant
    latestVersion = allVersions{end};
    latestVariants = versionMap(latestVersion);
    currentArch = mip.arch();
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

    if ~isempty(compatibleVariant) && isfield(compatibleVariant, 'dependencies') && ~isempty(compatibleVariant.dependencies)
        deps = compatibleVariant.dependencies;
        if ~iscell(deps)
            deps = {deps};
        end
        fprintf('\n  Dependencies (latest):\n');
        for i = 1:length(deps)
            fprintf('    - %s\n', deps{i});
        end
    end

    fprintf('\n');
end


function sorted = sortVersions(versions)
    n = length(versions);
    sorted = versions;
    for i = 2:n
        key = sorted{i};
        j = i - 1;
        while j >= 1 && mip.resolve.compare_versions(sorted{j}, key) > 0
            sorted{j+1} = sorted{j};
            j = j - 1;
        end
        sorted{j+1} = key;
    end
end
