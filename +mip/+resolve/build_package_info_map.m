function [packageInfoMap, unavailablePackages] = build_package_info_map(index, org, channelName, requestedVersions)
%BUILD_PACKAGE_INFO_MAP   Build a map from package FQN to best variant info.
%
% Args:
%   index             - Parsed index struct (from fetch_index)
%   org               - Organization name (e.g. 'mip-org')
%   channelName       - Channel name (e.g. 'core')
%   requestedVersions - (optional) containers.Map of bare name -> version string.
%                       When a version is specified for a package, that version
%                       is used instead of the automatic best-version selection.
%
% Returns:
%   packageInfoMap      - containers.Map: FQN -> best variant struct
%   unavailablePackages - containers.Map: FQN -> cell array of available architectures

if nargin < 4
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
end

currentArch = mip.build.arch();
packages = index.packages;

% Group packages by name, then by version. Names that differ only in case
% or in `-` vs `_` are merged (mip.name.match equivalence). The first
% form encountered wins as the display form for that name.
% normalizedToDisplay: normalized name -> display name used as nameMap key
% nameMap: display name -> containers.Map(version -> cell array of variants)
normalizedToDisplay = containers.Map('KeyType', 'char', 'ValueType', 'char');
nameMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:length(packages)
    if iscell(packages)
        pkg = packages{i};
    else
        pkg = packages(i);
    end

    if ~isstruct(pkg)
        error('mip:invalidPackageFormat', 'Invalid package format in index');
    end

    pkgName = pkg.name;
    pkgVersion = pkg.version;
    normName = mip.name.normalize(pkgName);

    if normalizedToDisplay.isKey(normName)
        displayName = normalizedToDisplay(normName);
    else
        displayName = pkgName;
        normalizedToDisplay(normName) = displayName;
    end

    if ~nameMap.isKey(displayName)
        nameMap(displayName) = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end
    versionMap = nameMap(displayName);

    if ~versionMap.isKey(pkgVersion)
        versionMap(pkgVersion) = {};
    end
    variants = versionMap(pkgVersion);
    versionMap(pkgVersion) = [variants, {pkg}];
end

% For each package name, select best version then best variant
packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
unavailablePackages = containers.Map('KeyType', 'char', 'ValueType', 'any');

packageNames = keys(nameMap);
for i = 1:length(packageNames)
    pkgName = packageNames{i};
    versionMap = nameMap(pkgName);
    allVersions = keys(versionMap);

    % Select version. requestedVersions may be keyed by a name with
    % different case/separators than pkgName, so look up case-insensitively.
    requestedVersion = lookup_requested_version(requestedVersions, pkgName);
    if ~isempty(requestedVersion)
        chosenVersion = requestedVersion;
        if ~versionMap.isKey(chosenVersion)
            error('mip:versionNotFound', ...
                  'Version "%s" not found for package "%s". Available versions: %s', ...
                  chosenVersion, pkgName, strjoin(allVersions, ', '));
        end
    else
        chosenVersion = mip.resolve.select_best_version(allVersions);
    end

    % Select best variant for the chosen version
    variants = versionMap(chosenVersion);
    bestVariant = mip.resolve.select_best_variant(variants, currentArch);

    fqn = mip.parse.make_fqn(org, channelName, pkgName);

    if ~isempty(bestVariant)
        packageInfoMap(fqn) = bestVariant;
    else
        availableArchs = {};
        for j = 1:length(variants)
            availableArchs = [availableArchs, {variants{j}.architecture}]; %#ok<AGROW>
        end
        unavailablePackages(fqn) = unique(availableArchs);
    end
end

end

function v = lookup_requested_version(requestedVersions, pkgName)
% Case-insensitive (mip.name.match equivalence) lookup of pkgName in
% requestedVersions. Returns '' if no matching key exists.
v = '';
if isempty(requestedVersions) || requestedVersions.Count == 0
    return
end
if requestedVersions.isKey(pkgName)
    v = requestedVersions(pkgName);
    return
end
ks = keys(requestedVersions);
for i = 1:length(ks)
    if mip.name.match(ks{i}, pkgName)
        v = requestedVersions(ks{i});
        return
    end
end
end
