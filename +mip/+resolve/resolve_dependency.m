function depFqn = resolve_dependency(depName, dependingPkgFqn)
%RESOLVE_DEPENDENCY   Resolve a dependency name to a fully qualified name.
%
% If depName is already a FQN, return as-is.
%
% If depName is a bare name, prefer the depending package's own channel:
% if the dep is installed at gh/<owner>/<channel>/<name> for the same
% <owner>/<channel> as the depending package, return that FQN. Otherwise
% fall back to gh/mip-org/core/<name>.
%
% This lets a package on owner/chan list bare deps that today live on
% owner/chan and tomorrow may move to mip-org/core — once the core
% version is what's installed, bare names automatically retarget there.
%
% Args:
%   depName         - Dependency name (bare or FQN)
%   dependingPkgFqn - (Optional) FQN of the package whose mip.yaml lists
%                     this dep. Used only for bare-name resolution; if
%                     omitted or not a gh FQN, bare names resolve
%                     directly to mip-org/core.
%
% Returns:
%   depFqn - Fully qualified name

result = mip.parse.parse_package_arg(depName);

if result.is_fqn
    depFqn = result.fqn;
    return
end

if nargin >= 2 && ~isempty(dependingPkgFqn)
    parent = mip.parse.parse_package_arg(dependingPkgFqn);
    if parent.is_fqn && strcmp(parent.type, 'gh') ...
            && ~(strcmp(parent.owner, 'mip-org') && strcmp(parent.channel, 'core'))
        sameChannelFqn = mip.parse.make_fqn(parent.owner, parent.channel, result.name);
        if mip.state.is_installed(sameChannelFqn)
            depFqn = sameChannelFqn;
            return
        end
    end
end

depFqn = mip.parse.make_fqn('mip-org', 'core', result.name);

end
