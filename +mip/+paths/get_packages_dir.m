function packagesDir = get_packages_dir()
%GET_PACKAGES_DIR   Get the mip packages directory path.
%
% Returns:
%   Path to the packages directory (Default: ~/.mip/packages)

mipDir = mip.root();
packagesDir = fullfile(mipDir, 'packages');

end
