function discard_backups(backups)
%DISCARD_BACKUPS   Delete backup directories after a successful replacement.
%
% The backups are the replaced old packages; they may carry binaries that
% were loaded earlier in the session, so removal is routed through the
% robust trash-based mip.paths.remove_dir.

    for i = 1:length(backups)
        mip.paths.remove_dir(backups(i).backupDir);
    end
end
