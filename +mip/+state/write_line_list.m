function write_line_list(file, lines)
%WRITE_LINE_LIST   Atomically write a cell array of lines to a text file.
%
% Shared writer for the line-per-entry state files under <root>/packages/
% (directly_installed.txt, pinned.txt, channels.txt). Writes each entry on
% its own line via a temp file that is renamed into place, so a reader
% never observes a half-written file.
%
% The <root>/packages/ directory is created if it does not exist. Callers
% are responsible for ordering `lines` as they should appear on disk.
%
% Args:
%   file  - Absolute path to the destination file.
%   lines - Cell array of strings, one per line, in on-disk order.

packagesDir = fileparts(file);
if ~exist(packagesDir, 'dir')
    mkdir(packagesDir);
end

tmpFile = [file '.tmp'];
fid = fopen(tmpFile, 'w');
if fid == -1
    error('mip:fileError', 'Could not write to %s', tmpFile);
end

try
    for i = 1:length(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fclose(fid);
catch ME
    fclose(fid);
    if exist(tmpFile, 'file')
        delete(tmpFile);
    end
    rethrow(ME);
end

[ok, msg] = movefile(tmpFile, file, 'f');
if ~ok
    if exist(tmpFile, 'file')
        delete(tmpFile);
    end
    error('mip:fileError', 'Could not rename tmp file into place: %s', msg);
end

end
