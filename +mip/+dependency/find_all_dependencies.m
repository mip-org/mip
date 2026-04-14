function deps = find_all_dependencies(fqn)
%FIND_ALL_DEPENDENCIES   Recursively collect all transitive dependencies of an installed package.
%
% Reads mip.json from the installed package directory and resolves bare
% dependency names to mip-org/core/<name>.
%
% Args:
%   fqn - Fully qualified package name (org/channel/name)
%
% Returns:
%   deps - Cell array of dependency FQNs (transitive closure, not including fqn itself)

deps = {};

result = mip.parse.parse_package_arg(fqn);
if ~result.is_fqn
    return
end

packageDir = mip.paths.get_package_dir(result.org, result.channel, result.name);
mipJsonPath = fullfile(packageDir, 'mip.json');

if ~exist(mipJsonPath, 'file')
    return
end

try
    pkgInfo = mip.config.read_package_json(packageDir);

    if isempty(pkgInfo.dependencies)
        return
    end

    depNames = pkgInfo.dependencies;
    for i = 1:length(depNames)
        dep = depNames{i};
        try
            depFqn = mip.resolve.resolve_dependency(dep);
        catch
            continue
        end
        if ~ismember(depFqn, deps)
            deps{end+1} = depFqn; %#ok<AGROW>
            transitiveDeps = mip.dependency.find_all_dependencies(depFqn);
            deps = unique([deps, transitiveDeps]);
        end
    end
catch ME
    warning('mip:jsonParseError', ...
            'Could not parse mip.json for package "%s": %s', ...
            fqn, ME.message);
end

end
