function sweep_path_entries(envPath)
%SWEEP_PATH_ENTRIES   Remove MATLAB path entries under an environment root.
%
% Usage:
%   mip.env.sweep_path_entries(envPath)
%
% Backstop after unloading an environment's packages: removes any
% remaining path entries under the environment root, covering the case
% where the directory was deleted out from under the session and unload
% could not resolve source dirs from mip.json.

prefixWithSep = [envPath, filesep];
entries = strsplit(path, pathsep);
oldState = warning('off', 'MATLAB:rmpath:DirNotFound');
restoreWarn = onCleanup(@() warning(oldState)); %#ok<NASGU>
for k = 1:numel(entries)
    e = entries{k};
    if isempty(e)
        continue
    end
    if strcmp(e, envPath) || startsWith(e, prefixWithSep)
        rmpath(e);
    end
end

end
