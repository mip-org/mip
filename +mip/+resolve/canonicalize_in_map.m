function canonicalFqn = canonicalize_in_map(fqn, packageInfoMap)
%CANONICALIZE_IN_MAP   Canonicalize an FQN against a packageInfoMap.
%
% Scans the packageInfoMap keys (which are FQN strings keyed by channel-
% canonical names) for a key whose name matches under the equivalence
% rules of mip.name.match. If found, returns that key (the channel-
% canonical FQN). Otherwise returns the input fqn unchanged.
%
% Used at the boundary between user-typed names and the channel index,
% so that the rest of install.m operates on channel-canonical names. The
% on-disk install path then matches what other commands look up.
%
% Args:
%   fqn            - FQN string (e.g. 'mip-org/core/MyPkg')
%   packageInfoMap - containers.Map: FQN string -> variant struct
%
% Returns:
%   canonicalFqn - The matching key from packageInfoMap, or the input fqn

canonicalFqn = fqn;

if isempty(packageInfoMap) || packageInfoMap.Count == 0
    return
end

if packageInfoMap.isKey(fqn)
    return
end

target = mip.parse.parse_package_arg(fqn);
mapKeys = keys(packageInfoMap);
for i = 1:length(mapKeys)
    k = mapKeys{i};
    parsed = mip.parse.parse_package_arg(k);
    if strcmp(parsed.org, target.org) && ...
            strcmp(parsed.channel, target.channel) && ...
            mip.name.match(parsed.name, target.name)
        canonicalFqn = k;
        return
    end
end

end
