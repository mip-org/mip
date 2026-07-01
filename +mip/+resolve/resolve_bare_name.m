function fqn = resolve_bare_name(packageName)
%RESOLVE_BARE_NAME   Resolve a bare package name to its fully qualified name.
%
% Searches installed packages for a name match under the equivalence
% rules of mip.name.match (case-insensitive, dash/underscore-equivalent).
% Resolution priority:
%   1. gh/mip-org/core (the default channel)
%   2. First alphabetically by FQN
%
% The returned FQN uses the actual on-disk directory name, which may
% differ in case or separators from the input.
%
% Args:
%   packageName - Bare package name (e.g. 'chebfun')
%
% Returns:
%   fqn - Canonical FQN, or empty string if not found

fqn = '';

% find_all_installed_by_name returns the name matches in sorted order.
matches = mip.resolve.find_all_installed_by_name(packageName);
if isempty(matches)
    return
end

% Priority: gh/mip-org/core first
for i = 1:length(matches)
    if startsWith(matches{i}, 'gh/mip-org/core/')
        fqn = matches{i};
        return
    end
end

% Otherwise the alphabetically-first FQN.
fqn = matches{1};

end
