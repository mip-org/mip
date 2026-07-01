function packages = get_directly_installed()
%GET_DIRECTLY_INSTALLED   Get list of directly installed packages.
%
% Returns:
%   packages - Cell array of package names that were directly installed

    directFile = fullfile(mip.paths.get_packages_dir(), 'directly_installed.txt');
    packages = mip.state.read_line_list(directFile);
end
