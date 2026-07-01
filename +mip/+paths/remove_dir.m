function remove_dir(dirPath)
%REMOVE_DIR   Robustly remove a directory.
%
% Removes dirPath by first moving it into the mip trash area
% (mip.paths.get_trash_dir) under a random name, then attempting to delete it
% from there. The move-first strategy makes removal robust against files
% that cannot be deleted in the current MATLAB session -- notably on
% Windows, where the OS refuses to delete a DLL/MEX that is still loaded
% (an OpenMP MEX, for instance, pins its DLL for the life of the process).
% A rename always succeeds, so the directory disappears from its original
% location immediately; if the subsequent delete fails, the moved copy is
% left in the trash for mip.paths.purge_trash to remove on a later mip run,
% once nothing has the binary loaded.
%
% This is the single removal path for installed package directories and the
% backups created while replacing them (uninstall, prune, update, install).
%
% A no-op if dirPath does not exist. Raises mip:removeDirFailed only if the
% directory cannot even be moved into the trash.

    if ~exist(dirPath, 'dir')
        return
    end

    trashDir = mip.paths.get_trash_dir();
    if ~exist(trashDir, 'dir')
        mkdir(trashDir);
    end

    dest = tempname(trashDir);
    [moved, msg] = movefile(dirPath, dest, 'f');
    if ~moved
        error('mip:removeDirFailed', ...
              'Failed to remove directory "%s": %s', dirPath, msg);
    end

    % Attempt to delete from the trash. A failure here is non-fatal: the
    % directory is already gone from its original location, and the leftover
    % is swept by purge_trash on a later run.
    [ok, ~] = rmdir(dest, 's');
    if ~ok
        fprintf(['  Note: "%s" could not be fully deleted (a file may be in ' ...
                 'use by this MATLAB session); moved to the mip trash for ' ...
                 'cleanup on a later mip run.\n'], dirPath);
    end
end
