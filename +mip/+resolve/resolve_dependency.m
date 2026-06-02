function depFqn = resolve_dependency(depName, parentFqn)
%RESOLVE_DEPENDENCY   Resolve a dependency name to a fully qualified name.
%
% If depName is already a FQN, return it unchanged.
%
% For a bare name, resolve relative to the depending package's own channel:
% if parentFqn is a gh FQN on a channel other than mip-org/core, and that
% channel has the dependency installed, resolve to
% <parentOwner>/<parentChannel>/<name>. Otherwise -- no parent given, a
% mip-org/core parent, or the dependency is not installed in the parent's
% channel -- resolve to mip-org/core/<name>, as before.
%
% This lets a package in a non-core channel depend, by bare name, on
% sibling packages published in that same channel, while bare deps in
% mip-org/core packages keep resolving to mip-org/core. To depend on a
% package from an unrelated channel, use its fully qualified name in
% mip.yaml.
%
% Args:
%   depName   - Dependency name (bare or FQN)
%   parentFqn - (Optional) FQN of the package that declares this dependency
%
% Returns:
%   depFqn - Fully qualified name

if nargin < 2
    parentFqn = '';
end

result = mip.parse.parse_package_arg(depName);

if result.is_fqn
    depFqn = result.fqn;
    return
end

% Prefer the depending package's own channel (when it is not the default
% mip-org/core channel) if that channel actually has the dependency
% installed. Falling through to mip-org/core preserves prior behavior.
if ~isempty(parentFqn)
    p = mip.parse.parse_package_arg(parentFqn);
    if p.is_fqn && strcmp(p.type, 'gh') ...
            && ~(strcmp(p.owner, 'mip-org') && strcmp(p.channel, 'core'))
        ownFqn = mip.parse.make_fqn(p.owner, p.channel, result.name);
        if ~isempty(mip.resolve.installed_dir(ownFqn))
            depFqn = ownFqn;
            return
        end
    end
end

depFqn = mip.parse.make_fqn('mip-org', 'core', result.name);

end
