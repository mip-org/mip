function restore_dir(backupDir, dir)
%RESTORE_DIR   Restore a directory previously moved to a backup.
%
% Undoes mip.paths.backup_dir after a failed replacement: removes any
% partial replacement left at `dir`, recreates its parent directory if
% needed, and moves the backup back into place. No-op if the backup no
% longer exists.
%
% Args:
%   backupDir - Backup path returned by mip.paths.backup_dir
%   dir       - Original directory path to restore to

if exist(dir, 'dir')
    mip.paths.remove_dir(dir);
end
parentDir = fileparts(dir);
if ~exist(parentDir, 'dir')
    mkdir(parentDir);
end
if exist(backupDir, 'dir')
    movefile(backupDir, dir);
end

end
