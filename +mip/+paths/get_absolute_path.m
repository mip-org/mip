function absPath = get_absolute_path(relPath)
%GET_ABSOLUTE_PATH   Resolve a file or directory path to an absolute path.
%
% Args:
%   relPath - A relative or absolute file or directory path.
%
% Returns:
%   absPath - The absolute path to the file or directory.
%
% Errors if the file or directory does not exist.

absPath = matlab.io.internal.filesystem.resolveRelativeLocation(relPath);
if isempty(char(absPath)) || ~exist(absPath, 'file')
    error('mip:notAFileOrDirectory', '"%s" is not a file or directory.', relPath);
end

end
