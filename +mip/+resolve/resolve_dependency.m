function depFqn = resolve_dependency(depName, contextOrg, contextChannel)
%RESOLVE_DEPENDENCY   Resolve a dependency name to a fully qualified name.
%
% If depName is already a FQN, return as-is.
% If bare, try same channel first, then mip-org/core, then general resolution.
%
% Args:
%   depName        - Dependency name (bare or FQN)
%   contextOrg     - Org of the parent package
%   contextChannel - Channel of the parent package
%
% Returns:
%   depFqn - Fully qualified name, or error if not found

result = mip.parse.parse_package_arg(depName);

if result.is_fqn
    depFqn = depName;
    return
end

% Try same channel first
sameChannelDir = mip.paths.get_package_dir(contextOrg, contextChannel, result.name);
if exist(sameChannelDir, 'dir')
    depFqn = mip.parse.make_fqn(contextOrg, contextChannel, result.name);
    return
end

% Try mip-org/core
coreDir = mip.paths.get_package_dir('mip-org', 'core', result.name);
if exist(coreDir, 'dir')
    depFqn = mip.parse.make_fqn('mip-org', 'core', result.name);
    return
end

% Fall back to general resolution
depFqn = mip.resolve.resolve_bare_name(result.name);
if isempty(depFqn)
    error('mip:dependencyNotFound', ...
          'Dependency "%s" is not installed.', result.name);
end

end
