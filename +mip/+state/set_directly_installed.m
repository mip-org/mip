function set_directly_installed(packages)
%SET_DIRECTLY_INSTALLED   Set the list of directly installed packages.
%
% Args:
%   packages - Cell array of package names that are directly installed

    packagesDir = mip.paths.get_packages_dir();
    
    % Create packages directory if it doesn't exist
    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end
    
    directFile = fullfile(packagesDir, 'directly_installed.txt');
    
    % Sort packages for consistent ordering
    packages = sort(packages);
    
    fid = fopen(directFile, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to directly_installed.txt');
    end
    
    try
        for i = 1:length(packages)
            fprintf(fid, '%s\n', packages{i});
        end
        fclose(fid);
    catch ME
        fclose(fid);
        rethrow(ME);
    end
end
