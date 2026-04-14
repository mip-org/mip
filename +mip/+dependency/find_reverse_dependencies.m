function reverseDeps = find_reverse_dependencies(packageName, visited)
%FIND_REVERSE_DEPENDENCIES   Find all packages that depend on a given package.
%
% Args:
%   packageName - Bare name or FQN of the package to find reverse deps for
%   visited - (Optional) Cell array of already visited packages
%
% Returns:
%   reverseDeps - Cell array of FQNs that depend on the given package

if nargin < 2
    visited = {};
end

% Avoid infinite recursion
if ismember(packageName, visited)
    reverseDeps = {};
    return
end

visited = [visited, {packageName}];
reverseDeps = {};

% Get bare name for dependency matching
result = mip.parse.parse_package_arg(packageName);
bareName = result.name;

% Scan all installed packages
allPackages = mip.state.list_installed_packages();

for i = 1:length(allPackages)
    fqn = allPackages{i};

    % Skip the package itself
    if strcmp(fqn, packageName)
        continue
    end

    r = mip.parse.parse_package_arg(fqn);
    pkgDir = mip.paths.get_package_dir(r.org, r.channel, r.name);

    try
        pkgInfo = mip.config.read_package_json(pkgDir);
        dependencies = pkgInfo.dependencies;

        % Check if this package depends on our target (by bare name or FQN)
        if ismember(bareName, dependencies) || ismember(packageName, dependencies)
            reverseDeps = [reverseDeps, {fqn}]; %#ok<*AGROW>
            transitiveDeps = mip.dependency.find_reverse_dependencies(fqn, visited);
            reverseDeps = [reverseDeps, transitiveDeps];
        end
    catch
        continue
    end
end

reverseDeps = unique(reverseDeps, 'stable');

end
