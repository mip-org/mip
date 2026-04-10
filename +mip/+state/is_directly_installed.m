function direct = is_directly_installed(packageName)
%IS_DIRECTLY_INSTALLED   Check if a package is directly installed.
%
% Args:
%   packageName - Name of package to check
%
% Returns:
%   direct - True if package is directly installed

    packages = mip.state.get_directly_installed();
    direct = ismember(packageName, packages);
end
