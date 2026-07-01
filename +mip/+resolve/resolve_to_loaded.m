function fqn = resolve_to_loaded(packageName)
%RESOLVE_TO_LOADED   Resolve a bare name among currently loaded packages.
%
% Matches use the equivalence rules of mip.name.match (case-insensitive,
% dash/underscore-equivalent). If multiple loaded packages share the bare
% name, the most recently loaded one wins (MIP_LOADED_PACKAGES is kept in
% load order, so the last match is the most recent).
%
% Args:
%   packageName - Bare package name
%
% Returns:
%   fqn - FQN of the matching loaded package, or '' if none match.

fqn = '';
loadedPackages = mip.state.key_value_get('MIP_LOADED_PACKAGES');
for i = 1:length(loadedPackages)
    r = mip.parse.parse_package_arg(loadedPackages{i});
    if r.is_fqn && mip.name.match(r.name, packageName)
        fqn = loadedPackages{i};
    end
end

end
