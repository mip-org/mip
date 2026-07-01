function set_directly_installed(packages)
%SET_DIRECTLY_INSTALLED   Set the list of directly installed packages.
%
% Args:
%   packages - Cell array of package names that are directly installed

    directFile = fullfile(mip.paths.get_packages_dir(), 'directly_installed.txt');
    % Sort for consistent on-disk ordering.
    mip.state.write_line_list(directFile, sort(packages));
end
