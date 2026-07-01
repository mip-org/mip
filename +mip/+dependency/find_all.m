function deps = find_all(fqn, visited)
%FIND_ALL   Recursively collect all transitive dependencies of an installed package.
%
% Reads mip.json from the installed package directory and resolves bare
% dependency names to mip-org/core/<name>. Cycles are tolerated: a package
% already in `visited` is not re-entered.
%
% Args:
%   fqn     - Fully qualified package name (<owner>/<channel>/<name>)
%   visited - (Optional) Cell array of FQNs already being processed. Used
%             internally to break circular dependency chains.
%
% Returns:
%   deps - Cell array of dependency FQNs (transitive closure, not including fqn itself)

if nargin < 2
    visited = {};
end

deps = {};

result = mip.parse.parse_package_arg(fqn);
if ~result.is_fqn
    return
end

packageDir = mip.paths.get_package_dir(fqn);
mipJsonPath = fullfile(packageDir, 'mip.json');

if ~exist(mipJsonPath, 'file')
    return
end

visited = [visited, {fqn}];

try
    pkgInfo = mip.config.read_package_json(packageDir);

    if isempty(pkgInfo.dependencies)
        return
    end

    depNames = pkgInfo.dependencies;
    for i = 1:length(depNames)
        dep = depNames{i};
        try
            depFqn = mip.resolve.resolve_dependency(dep, fqn);
        catch
            continue
        end
        if ismember(depFqn, visited) || ismember(depFqn, deps)
            continue
        end
        deps{end+1} = depFqn; %#ok<AGROW>
        transitiveDeps = mip.dependency.find_all(depFqn, [visited, deps]);
        deps = unique([deps, transitiveDeps]);
    end
catch ME
    warning('mip:jsonParseError', ...
            'Could not parse mip.json for package "%s": %s', ...
            fqn, ME.message);
end

end
