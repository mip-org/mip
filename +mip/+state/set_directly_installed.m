function set_directly_installed(packages)
%SET_DIRECTLY_INSTALLED   Set the list of directly installed packages.
%
% Args:
%   packages - Cell array of package names that are directly installed

    packagesDir = mip.paths.get_packages_dir();

    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    directFile = fullfile(packagesDir, 'directly_installed.txt');
    tmpFile = [directFile '.tmp'];

    % Sort packages for consistent ordering
    packages = sort(packages);

    fid = fopen(tmpFile, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to directly_installed.txt.tmp');
    end

    try
        for i = 1:length(packages)
            fprintf(fid, '%s\n', packages{i});
        end
        fclose(fid);
    catch ME
        fclose(fid);
        if exist(tmpFile, 'file')
            delete(tmpFile);
        end
        rethrow(ME);
    end

    [ok, msg] = movefile(tmpFile, directFile, 'f');
    if ~ok
        if exist(tmpFile, 'file')
            delete(tmpFile);
        end
        error('mip:fileError', 'Could not rename tmp file into place: %s', msg);
    end
end
