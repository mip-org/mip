function cleared = clear_mex(dirPath)
%CLEAR_MEX   Unload every compiled MEX binary found under a directory.
%
% Walks dirPath recursively for MEX binaries (files matching *.mex*, any
% architecture's extension) and runs `clear` on each one's full path, so
% the binary is unloaded from the running MATLAB session. This lets the
% directory be deleted afterwards -- notably on Windows, where the OS
% refuses to delete a DLL/MEX that is still loaded.
%
% Called by mip.unload when a package is unloaded (so a later uninstall or
% update can delete the package directory) and by the mip self-uninstall,
% which clears the MEX of every installed package before deleting the mip
% root.
%
% Returns the full paths of the MEX files it cleared (for logging and
% testing). A no-op returning {} if dirPath is empty or not a directory.

    cleared = {};
    if isempty(dirPath) || ~isfolder(dirPath)
        return
    end

    info = dir(fullfile(dirPath, '**', '*.mex*'));
    for i = 1:numel(info)
        if info(i).isdir
            continue
        end
        mexPath = fullfile(info(i).folder, info(i).name);
        % Best-effort: a problematic entry must never abort the unload or
        % uninstall it is part of.
        try %#ok<TRYNC>
            clear(mexPath);
        end
        cleared{end+1} = mexPath; %#ok<AGROW>
    end
end
