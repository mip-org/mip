function dir = project_dir(directoryOpt)
%PROJECT_DIR   Resolve the project directory for a mip environment command.
%
% Args:
%   directoryOpt - Value of the --directory flag (may be empty).
%
% Returns:
%   dir - Absolute path to the project directory.
%
% When --directory is given, that path is used (and must exist). Otherwise
% the current working directory is used. This is the directory that holds
% mipenv.yaml and mipenv.lock, and whose ".mip" subdirectory is the
% project-local install root.
%
% NOTE: For this prototype, discovery does not walk up the directory tree
% the way uv/git do. The project directory is either explicit (--directory)
% or the current folder.

if nargin < 1 || isempty(directoryOpt)
    dir = pwd;
    return
end

dir = mip.paths.get_absolute_path(directoryOpt);
if exist(dir, 'dir') ~= 7
    error('mip:env:notADirectory', '"%s" is not a directory.', dir);
end

end
