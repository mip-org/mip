function remove_pinned(packageName)
%REMOVE_PINNED   Remove a package from the pinned list.
%
% Args:
%   packageName - FQN of package to unpin

    packages = mip.state.get_pinned();
    packages = packages(~strcmp(packages, packageName));
    mip.state.set_pinned(packages);
end
