function cleanup_empty_dirs(dirPath)
%CLEANUP_EMPTY_DIRS   Remove directory if it is empty (no subdirectories or files).

if ~exist(dirPath, 'dir')
    return
end
contents = dir(dirPath);
% Filter out . and ..
contents = contents(~ismember({contents.name}, {'.', '..'}));
if isempty(contents)
    rmdir(dirPath);
end

end
