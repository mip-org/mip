function restore_backups(backups)
%RESTORE_BACKUPS   Restore packages from backups after a failed replacement.
%
% For each backup created by mip.ops.backup_package: removes whatever now
% occupies the package directory, moves the backup back into place, and
% restores the package's directly-installed status. Failures are reported
% as warnings so one bad restore does not abort the others.

    for i = 1:length(backups)
        b = backups(i);
        try
            mip.paths.remove_dir(b.pkgDir);
            if exist(b.backupDir, 'dir')
                parentDir = fileparts(b.pkgDir);
                if ~exist(parentDir, 'dir')
                    mkdir(parentDir);
                end
                movefile(b.backupDir, b.pkgDir);
            end
            if b.wasDirectlyInstalled
                mip.state.add_directly_installed(b.fqn);
            end
        catch restoreErr
            warning('mip:rollbackFailed', ...
                    'Could not restore "%s" from backup: %s', ...
                    mip.parse.display_fqn(b.fqn), restoreErr.message);
        end
    end
end
