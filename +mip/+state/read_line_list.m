function lines = read_line_list(file, onUnreadable)
%READ_LINE_LIST   Read a text file into a cell array of non-empty lines.
%
% Shared reader for the line-per-entry state files under <root>/packages/
% (directly_installed.txt, pinned.txt, channels.txt). Each line is trimmed
% and blank lines are dropped.
%
% Args:
%   file         - Absolute path to the file.
%   onUnreadable - What to do when the file exists but cannot be opened:
%                    'empty' (default) - return {}
%                    'error'           - raise mip:fileError
%                  A missing file always returns {} regardless.
%
% Returns:
%   lines - Cell array of trimmed, non-empty lines in file order.

if nargin < 2
    onUnreadable = 'empty';
end

lines = {};
if ~exist(file, 'file')
    return
end

fid = fopen(file, 'r');
if fid == -1
    if strcmp(onUnreadable, 'error')
        error('mip:fileError', 'Could not read file: %s', file);
    end
    return
end
closer = onCleanup(@() fclose(fid));

while ~feof(fid)
    line = fgetl(fid);
    if ischar(line) && ~isempty(strtrim(line))
        lines{end+1} = strtrim(line); %#ok<AGROW>
    end
end

end
