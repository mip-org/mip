function [depList, missingFqns] = build_graph(packageFqn, packageInfoMap, visited, path)
%BUILD_GRAPH   Recursively build dependency graph for a package.
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
% mip-org/core/<name>. A repository package (gh/<owner>/<repo>) has no
% channel of its own, so its bare-name dependencies always resolve to
% mip-org/core. FQN dependencies are canonicalized against the fetched
% indexes (mip.resolve.canonicalize_in_map). A 2-part '<owner>/<name>'
% dependency means what it means to mip install: the repository
% github.com/<owner>/<name>, or the personal-channel package
% <owner>/<owner>/<name> if the repository publishes none (see
% resolveTwoPartDep).
%
% Example:
%   [deps, missing] = mip.dependency.build_graph('mip-org/core/mypackage', pkgMap);

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
    if ~isempty(depResult.fallback_fqn)
        depFqn = resolveTwoPartDep(dep, depResult, packageInfoMap);
    elseif depResult.is_fqn
        depFqn = mip.resolve.canonicalize_in_map(depResult.fqn, packageInfoMap);
    else
        depFqn = resolveBareDep(depResult.name, packageFqn, packageInfoMap);
    end

    [subDeps, subMissing] = mip.dependency.build_graph(depFqn, packageInfoMap, visited, path);
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
% otherwise fall back to mip-org/core/<name>. A repository parent's index
% provides only itself, so its bare-name dependencies go to mip-org/core. Mirrors the post-install rule
% in mip.resolve.resolve_dependency, using the channel index rather than
% installed state.
    p = mip.parse.parse_package_arg(parentFqn);
    if p.is_fqn && strcmp(p.type, 'gh') && ~p.is_repo ...
            && ~(strcmp(p.owner, 'mip-org') && strcmp(p.channel, 'core'))
        ownFqn = mip.parse.make_fqn(p.owner, p.channel, name);
        if isKey(packageInfoMap, ownFqn)
            depFqn = ownFqn;
            return
        end
    end
    depFqn = mip.parse.make_fqn('mip-org', 'core', name);
end

function depFqn = resolveTwoPartDep(dep, depResult, packageInfoMap)
% Resolve a 2-part '<owner>/<name>' dependency. A copy that is already
% installed, as either the repository or the personal-channel package, is
% kept, so a later dependent does not pull in a second copy under the
% other FQN. Otherwise the repository wins if its index is already in
% packageInfoMap (it publishes the package); if not, mip.resolve.repo_arg
% decides (the fetch, including a 404, is cached by fetch_index). A
% result missing from packageInfoMap is reported as missing, so the caller
% fetches its index and retries.
    installed = mip.resolve.installed_fqn(dep);
    if ~isempty(installed)
        depFqn = mip.resolve.canonicalize_in_map(installed, packageInfoMap);
        return
    end
    depFqn = mip.resolve.canonicalize_in_map(depResult.fqn, packageInfoMap);
    if isKey(packageInfoMap, depFqn)
        return
    end
    [owner, ch, name] = mip.resolve.repo_arg(depResult);
    depFqn = mip.resolve.canonicalize_in_map(mip.parse.make_fqn(owner, ch, name), packageInfoMap);
end
