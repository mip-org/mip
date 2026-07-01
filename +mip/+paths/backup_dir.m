function backupDir = backup_dir(dir)
%BACKUP_DIR   Move a directory to a temporary backup location.
%
% Pairs with mip.paths.restore_dir: install/update flows move the old
% package directory to a backup before putting a replacement in place,
% restore it if the replacement fails, and remove it
% (mip.paths.remove_dir) once the replacement succeeds.
%
% Args:
%   dir - Directory to move to a backup location
%
% Returns:
%   backupDir - Temporary path the directory was moved to

backupDir = [tempname '_mip_backup'];
movefile(dir, backupDir);

end
