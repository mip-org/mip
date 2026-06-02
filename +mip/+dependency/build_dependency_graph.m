function [depList, missingFqns] = build_dependency_graph(packageFqn, packageInfoMap, visited, path)
%BUILD_DEPENDENCY_GRAPH   Recursively build dependency graph for a package.
%
% Args:
%   packageFqn     - Fully qualified package name (<owner>/<channel>/<name>)
%   packageInfoMap - containers.Map of FQN -> package info
%   visited        - (Optional) Cell array of already visited FQNs
%   path           - (Optional) Cell array representing current dependency path
%
% Returns:
%   depList     - Cell array of FQNs in dependency order (dependencies first)
%   missingFqns - Cell array of FQNs that were not found in packageInfoMap.
%                 When non-empty, depList is incomplete. The caller should
%                 fetch the channels for the missing packages and retry.
%
% Bare-name dependencies resolve to the depending package's own channel
% when that channel's index (packageInfoMap) provides them, otherwise to
% mip-org/core/<name>.
%
% Example:
%   [deps, missing] = mip.dependency.build_dependency_graph('mip-org/core/mypackage', pkgMap);

if nargin < 3
    visited = {};
end
if nargin < 4
    path = {};
end

missingFqns = {};

% Check for circular dependency
if ismember(packageFqn, path)
    cycle = strjoin([path, {packageFqn}], ' -> ');
    error('mip:circularDependency', ...
          'Circular dependency detected: %s', cycle);
end

% If already visited, skip
if ismember(packageFqn, visited)
    depList = {};
    return
end

% Find package info
if ~isKey(packageInfoMap, packageFqn)
    depList = {};
    missingFqns = {packageFqn};
    return
end
pkgInfo = packageInfoMap(packageFqn);

% Mark as visited and add to path
visited = [visited, {packageFqn}];
path = [path, {packageFqn}];

% Collect all dependencies first
depList = {};
dependencies = pkgInfo.dependencies;

for i = 1:length(dependencies)
    dep = dependencies{i};
    depResult = mip.parse.parse_package_arg(dep);
    if depResult.is_fqn
        depFqn = depResult.fqn;
    else
        depFqn = resolveBareDep(depResult.name, packageFqn, packageInfoMap);
    end

    [subDeps, subMissing] = mip.dependency.build_dependency_graph(depFqn, packageInfoMap, visited, path);
    depList = [depList, subDeps]; %#ok<*AGROW>
    missingFqns = [missingFqns, subMissing];
end

% Then add this package
depList = [depList, {packageFqn}];

end

function depFqn = resolveBareDep(name, parentFqn, packageInfoMap)
% Resolve a bare-name dependency relative to the depending package's
% channel: prefer <parentOwner>/<parentChannel>/<name> when the parent is
% on a non-core channel and that channel's fetched index provides it,
% otherwise fall back to mip-org/core/<name>. Mirrors the post-install rule
% in mip.resolve.resolve_dependency, using the channel index rather than
% installed state.
    p = mip.parse.parse_package_arg(parentFqn);
    if p.is_fqn && strcmp(p.type, 'gh') ...
            && ~(strcmp(p.owner, 'mip-org') && strcmp(p.channel, 'core'))
        ownFqn = mip.parse.make_fqn(p.owner, p.channel, name);
        if isKey(packageInfoMap, ownFqn)
            depFqn = ownFqn;
            return
        end
    end
    depFqn = mip.parse.make_fqn('mip-org', 'core', name);
end
