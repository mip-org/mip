function [packageInfoMap, unavailablePackages] = build_package_info_map(index)
%BUILD_PACKAGE_INFO_MAP   Build a map from package name to best variant info.
%
% Args:
%   index - Parsed index struct (from fetch_index)
%
% Returns:
%   packageInfoMap - containers.Map: package name -> best variant struct
%   unavailablePackages - containers.Map: package name -> cell array of available architectures

currentArch = mip.arch();
packages = index.packages;

% Group packages by name
packagesByName = containers.Map('KeyType', 'char', 'ValueType', 'any');
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
    if ~packagesByName.isKey(pkgName)
        packagesByName(pkgName) = {};
    end
    variants = packagesByName(pkgName);
    packagesByName(pkgName) = [variants, {pkg}];
end

% Select best variant for each package
packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
unavailablePackages = containers.Map('KeyType', 'char', 'ValueType', 'any');

packageNames = keys(packagesByName);
for i = 1:length(packageNames)
    pkgName = packageNames{i};
    variants = packagesByName(pkgName);
    bestVariant = mip.utils.select_best_variant(variants, currentArch);

    if ~isempty(bestVariant)
        packageInfoMap(pkgName) = bestVariant;
    else
        availableArchs = {};
        for j = 1:length(variants)
            availableArchs = [availableArchs, {variants{j}.architecture}]; %#ok<AGROW>
        end
        unavailablePackages(pkgName) = unique(availableArchs);
    end
end

end
