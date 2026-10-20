function missing = find_missing(deps, parentFqn)
%FIND_MISSING   Resolve dependency names and return the uninstalled ones.
%
% Each dependency (bare name or FQN) is resolved via
% mip.resolve.resolve_dependency relative to parentFqn. Returns the
% resolved FQNs that are not installed. A 2-part '<owner>/<name>'
% dependency that is installed in neither of its forms is returned as
% written, so that mip.install.from_repository resolves it as it would
% the same argument on the command line (repository, else personal
% channel).
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
    if mip.state.is_installed(depFqn)
        continue
    end
    if ~isempty(mip.parse.parse_package_arg(deps{i}).fallback_fqn)
        depFqn = deps{i};
    end
    missing{end+1} = depFqn; %#ok<AGROW>
end

end
