function missing = find_missing(deps, parentFqn)
%FIND_MISSING   Resolve dependency names and return the uninstalled ones.
%
% Each dependency (bare name or FQN) is resolved via
% mip.resolve.resolve_dependency relative to parentFqn. Returns the
% resolved FQNs that are not installed.
%
% Args:
%   deps      - Cell array of dependency names from mip.yaml / mip.json
%   parentFqn - FQN of the package declaring the dependencies
%
% Returns:
%   missing - Cell array of resolved dependency FQNs not installed.

missing = {};
for i = 1:length(deps)
    depFqn = mip.resolve.resolve_dependency(deps{i}, parentFqn);
    if ~mip.state.is_installed(depFqn)
        missing{end+1} = depFqn; %#ok<AGROW>
    end
end

end
