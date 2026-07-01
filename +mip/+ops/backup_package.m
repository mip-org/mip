function backup = backup_package(fqn)
%BACKUP_PACKAGE   Move an installed package directory aside as a backup.
%
% Moves the package's directory to a temporary backup location and clears
% its directly-installed status (recording whether it had it). Together
% with mip.ops.restore_backups and mip.ops.discard_backups this is the
% transactional primitive for replacing an installed package: back up,
% attempt the replacement, then either restore (failure) or discard
% (success).
%
% Args:
%   fqn - Canonical FQN of the installed package.
%
% Returns:
%   backup - Struct with fields fqn, pkgDir, backupDir, and
%            wasDirectlyInstalled. Backups from multiple calls can be
%            accumulated into a struct array and passed together to
%            restore_backups / discard_backups.

    pkgDir = mip.paths.get_package_dir(fqn);
    wasDirectlyInstalled = mip.state.is_directly_installed(fqn);
    backupDir = [tempname '_mip_backup'];
    movefile(pkgDir, backupDir);
    if wasDirectlyInstalled
        mip.state.remove_directly_installed(fqn);
    end
    backup = struct( ...
        'fqn', fqn, ...
        'pkgDir', pkgDir, ...
        'backupDir', backupDir, ...
        'wasDirectlyInstalled', wasDirectlyInstalled);
end
