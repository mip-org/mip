function remove_directly_installed(packageName)
%REMOVE_DIRECTLY_INSTALLED   Remove a package from the directly installed list.
%
% Args:
%   packageName - Name of package to remove

    packages = mip.state.get_directly_installed();
    packages = packages(~strcmp(packages, packageName));
    mip.state.set_directly_installed(packages);
end
