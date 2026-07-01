function d = trash_dir()
%TRASH_DIR   Path to the mip trash area used for deferred directory deletion.
%
% Lives beside packages/ under the mip root, so it is outside the scanned
% package tree. Directories that cannot be deleted immediately -- notably a
% Windows MEX/DLL still loaded in the current MATLAB session -- are moved
% here by mip.paths.remove_dir and swept later by mip.paths.purge_trash.

    d = fullfile(mip.paths.root(), '.trash');
end
