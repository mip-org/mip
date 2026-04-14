function sortedPackages = topological_sort(packageFqns, packageInfoMap)
%TOPOLOGICAL_SORT   Sort packages in topological order (dependencies first).
%
% Args:
%   packageFqns    - Cell array of fully qualified package names to sort
%   packageInfoMap - containers.Map of FQN -> package info
%
% Returns:
%   sortedPackages - Cell array of FQNs in topological order
%
% Bare-name dependencies are always resolved to mip-org/core/<name>.
%
% Example:
%   sorted = mip.dependency.topological_sort({'mip-org/core/pkg1', 'mip-org/core/pkg2'}, pkgMap);

if isempty(packageFqns)
    sortedPackages = {};
    return
end

% Build adjacency list (FQN -> list of dependency names from metadata)
dependencies = containers.Map('KeyType', 'char', 'ValueType', 'any');

for i = 1:length(packageFqns)
    pkgFqn = packageFqns{i};

    % Get package info
    if isKey(packageInfoMap, pkgFqn)
        pkgInfo = packageInfoMap(pkgFqn);
    else
        pkgInfo = struct('dependencies', {{}});
    end

    % Get dependencies
    if isfield(pkgInfo, 'dependencies')
        deps = pkgInfo.dependencies;
    else
        deps = {};
    end

    dependencies(pkgFqn) = deps;
end

% Topological sort using DFS
visited = containers.Map('KeyType', 'char', 'ValueType', 'logical');
sortedPackages = {};

    function visit(pkgFqn)
        if visited.isKey(pkgFqn)
            return
        end
        visited(pkgFqn) = true;

        % Visit dependencies first
        if dependencies.isKey(pkgFqn)
            deps = dependencies(pkgFqn);
            for j = 1:length(deps)
                dep = deps{j};
                depResult = mip.parse.parse_package_arg(dep);
                if depResult.is_fqn
                    depFqn = dep;
                else
                    depFqn = mip.parse.make_fqn('mip-org', 'core', depResult.name);
                end
                if ismember(depFqn, packageFqns)
                    visit(depFqn);
                end
            end
        end

        sortedPackages = [sortedPackages, {pkgFqn}];
    end

% Visit all packages
for i = 1:length(packageFqns)
    visit(packageFqns{i});
end

end
