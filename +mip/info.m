function info(varargin)
%INFO   Display detailed information about a package.
%
% Usage:
%   mip info <package>
%   mip info org/channel/<package>
%   mip info --channel dev <package>
%   mip info --channel owner/chan <package>
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

% Find all local installations of this package, and collect which channels
% to query for remote info.
result = mip.parse.parse_package_arg(packageArg);
packageName = result.name;

if result.is_fqn
    % FQN: only check that specific installation. Canonicalize the name
    % to the on-disk form so we report and operate on the canonical FQN.
    onDisk = mip.resolve.installed_dir(result.fqn);
    if ~isempty(onDisk)
        if strcmp(result.type, 'gh')
            installedFqns = {mip.parse.make_fqn(result.org, result.channel, onDisk)};
        else
            installedFqns = {[result.type '/' onDisk]};
        end
    else
        installedFqns = {};
    end
else
    % Bare name: find all installations across channels
    installedFqns = mip.resolve.find_all_installed_by_name(packageName);
end

% ---- Collect channels to query ----

% For a gh FQN, query its specific channel. For bare names and non-gh FQNs,
% fall back to the --channel flag (default mip-org/core).
channelsToQuery = {};
if result.is_fqn && strcmp(result.type, 'gh')
    channelsToQuery{end+1} = [result.org '/' result.channel]; %#ok<AGROW>
elseif ~result.is_fqn
    [chOrg, chName] = mip.parse.parse_channel_spec(channel);
    channelsToQuery{end+1} = [chOrg '/' chName];
end
for i = 1:length(installedFqns)
    r = mip.parse.parse_package_arg(installedFqns{i});
    % Skip non-gh packages — no remote channel index exists for them.
    if ~strcmp(r.type, 'gh')
        continue
    end
    ch = [r.org '/' r.channel];
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
    if isempty(channelsToQuery)
        error('mip:unknownPackage', ...
            'Unknown package "%s".', packageName);
    else
        error('mip:unknownPackage', ...
            'Unknown package "%s" in channel "%s".', ...
            packageName, strjoin(channelsToQuery, '", "'));
    end
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

    pkgDir = mip.paths.get_package_dir(fqn);

    fprintf('\n  %s\n', mip.parse.display_fqn(fqn));

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
        fprintf('    Dependencies: %s\n', strjoin(deps, ', '));
    else
        fprintf('    Dependencies: None\n');
    end

    % Extra path groups (opt-in via `mip load --with <group>`)
    if isfield(pkgInfo, 'extra_paths') && isstruct(pkgInfo.extra_paths) ...
            && ~isempty(fieldnames(pkgInfo.extra_paths))
        groupNames = fieldnames(pkgInfo.extra_paths);
        fprintf('    Extra paths: %s\n', strjoin(groupNames, ', '));
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
% Check if a package exists in a pre-fetched index. Match by name
% equivalence (case- and dash/underscore-insensitive).
    found = false;
    packages = index.packages;
    for i = 1:length(packages)
        if iscell(packages)
            pkg = packages{i};
        else
            pkg = packages(i);
        end
        if isstruct(pkg) && mip.name.match(pkg.name, packageName)
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

    % Find all variants of this package (match by name equivalence)
    packages = index.packages;
    packageVariants = {};
    for i = 1:length(packages)
        if iscell(packages)
            pkg = packages{i};
        else
            pkg = packages(i);
        end
        if isstruct(pkg) && mip.name.match(pkg.name, packageName)
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
