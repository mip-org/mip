function depFqn = resolve_dependency(depName, parentFqn)
%RESOLVE_DEPENDENCY   Resolve a dependency name to a fully qualified name.
%
% If depName is already a FQN, return it unchanged.
%
% For a bare name, resolution depends on where the depending package came
% from:
%
%   1. parentFqn is a gh FQN on a channel other than mip-org/core, and
%      that channel has the dependency installed: resolve to
%      <parentOwner>/<parentChannel>/<name>. This lets a package in a
%      non-core channel depend, by bare name, on sibling packages
%      published in that same channel.
%
%   2. parentFqn is a non-gh FQN -- local, fex, web or mhl -- and some
%      installed package matches the name: resolve to that one, by the
%      same rules mip.resolve.resolve_bare_name uses for a name typed on
%      the command line. A package installed from a local directory or
%      in editable mode is on no channel, so it has no channel of its own
%      to prefer, and resolving its bare dependencies to mip-org/core
%      would mean an installed dependency could never satisfy them: a
%      package being developed alongside its dependency could not be
%      installed at all, whatever channel it targets.
%
%   3. Otherwise -- no parent given, a mip-org/core parent, or the
%      dependency is not installed anywhere the rules above look --
%      resolve to mip-org/core/<name>, as before. A dependency that is
%      not installed yet is therefore still fetched from the default
%      channel.
%
% Note that rule 2 looks only at what is installed; it never changes
% where a missing dependency is fetched from. To depend on a package from
% an unrelated channel, use its fully qualified name in mip.yaml.
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

if ~isempty(parentFqn)
    p = mip.parse.parse_package_arg(parentFqn);
    if p.is_fqn && strcmp(p.type, 'gh')
        % Prefer the depending package's own channel (when it is not the
        % default mip-org/core channel) if that channel actually has the
        % dependency installed. Falling through to mip-org/core preserves
        % prior behavior.
        if ~(strcmp(p.owner, 'mip-org') && strcmp(p.channel, 'core'))
            ownFqn = mip.parse.make_fqn(p.owner, p.channel, result.name);
            if ~isempty(mip.resolve.installed_dir(ownFqn))
                depFqn = ownFqn;
                return
            end
        end
    elseif p.is_fqn
        % A non-gh parent (local, fex, web, mhl) belongs to no channel,
        % so there is no sibling channel to prefer. Take whatever is
        % installed under the name instead, so that a locally installed
        % or editable dependency satisfies the declaration.
        installedFqn = mip.resolve.resolve_bare_name(result.name);
        if ~isempty(installedFqn)
            depFqn = installedFqn;
            return
        end
    end
end

depFqn = mip.parse.make_fqn('mip-org', 'core', result.name);

end
