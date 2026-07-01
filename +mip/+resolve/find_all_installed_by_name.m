function matches = find_all_installed_by_name(packageName)
%FIND_ALL_INSTALLED_BY_NAME   Find all installed packages with a given bare name.
%
% Matches use the equivalence rules of mip.name.match (case-insensitive,
% dash/underscore-equivalent). Returned FQNs use the actual on-disk
% directory name for each match and include the 'gh/' prefix for
% GitHub channel packages.
%
% A view over mip.state.list_installed_packages (the single source of
% truth for the installed tree), filtered by name and sorted.
%
% Returns:
%   matches - Sorted cell array of canonical FQN strings for each
%             source-type / owner / channel combination where this name
%             is installed.

matches = {};
for fqn = mip.state.list_installed_packages()
    r = mip.parse.parse_package_arg(fqn{1});
    if mip.name.match(r.name, packageName)
        matches{end+1} = fqn{1}; %#ok<AGROW>
    end
end
matches = sort(matches);

end
