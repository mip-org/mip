function deps = get_all_dependencies(fqn)
%GET_ALL_DEPENDENCIES   Recursively collect all transitive dependencies of an installed package.
%
% Reads mip.json from the installed package directory and resolves bare
% dependency names using same-channel-first, then mip-org/core, then
% general resolution.
%
% Args:
%   fqn - Fully qualified package name (org/channel/name)
%
% Returns:
%   deps - Cell array of dependency FQNs (transitive closure, not including fqn itself)

deps = {};

result = mip.utils.parse_package_arg(fqn);
if ~result.is_fqn
    return
end

packageDir = mip.utils.get_package_dir(result.org, result.channel, result.name);
mipJsonPath = fullfile(packageDir, 'mip.json');

if ~exist(mipJsonPath, 'file')
    return
end

try
    pkgInfo = mip.utils.read_package_json(packageDir);

    if isempty(pkgInfo.dependencies)
        return
    end

    depNames = pkgInfo.dependencies;
    if ~iscell(depNames)
        depNames = {depNames};
    end
    for i = 1:length(depNames)
        dep = depNames{i};
        try
            depFqn = mip.utils.resolve_dependency(dep, result.org, result.channel);
        catch
            continue
        end
        if ~ismember(depFqn, deps)
            deps{end+1} = depFqn; %#ok<AGROW>
            transitiveDeps = mip.utils.get_all_dependencies(depFqn);
            deps = unique([deps, transitiveDeps]);
        end
    end
catch ME
    warning('mip:jsonParseError', ...
            'Could not parse mip.json for package "%s": %s', ...
            fqn, ME.message);
end

end
