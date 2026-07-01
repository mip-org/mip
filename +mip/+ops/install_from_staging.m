function install_from_staging(stagingDir, pkgDir)
%INSTALL_FROM_STAGING   Move an extracted package into its install location.
%
% Creates the parent directory if needed and moves stagingDir to pkgDir.
% If the move fails partway, any partial pkgDir is removed so a failed
% install never leaves a half-populated package directory behind.

    parentDir = fileparts(pkgDir);
    if ~exist(parentDir, 'dir')
        mkdir(parentDir);
    end
    try
        movefile(stagingDir, pkgDir);
    catch ME
        if exist(pkgDir, 'dir')
            rmdir(pkgDir, 's');
        end
        rethrow(ME);
    end
end
