function purge_trash()
%PURGE_TRASH   Best-effort deletion of directories left in the mip trash.
%
% mip.paths.remove_dir moves directories here and deletes them in place.
% Anything left behind could not be deleted at the time (e.g. a loaded
% Windows binary). This sweep retries deletion; entries still locked are
% left for a future run. Always best-effort -- it never errors.
%
% Called at the start of every mip install (and uninstall) so the trash is
% reclaimed once the binaries that pinned its contents are no longer loaded.

    trashDir = mip.paths.trash_dir();
    if ~exist(trashDir, 'dir')
        return
    end
    entries = dir(trashDir);
    for i = 1:numel(entries)
        nm = entries(i).name;
        if strcmp(nm, '.') || strcmp(nm, '..')
            continue
        end
        target = fullfile(trashDir, nm);
        if entries(i).isdir
            [~, ~] = rmdir(target, 's');
        else
            try %#ok<TRYNC>
                delete(target);
            end
        end
    end
end
