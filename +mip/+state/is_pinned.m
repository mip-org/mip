function tf = is_pinned(packageName)
%IS_PINNED   Check if a package is pinned.
%
% Args:
%   packageName - FQN of package to check
%
% Returns:
%   tf - true if the package is pinned

    packages = mip.state.get_pinned();
    tf = ismember(packageName, packages);
end
