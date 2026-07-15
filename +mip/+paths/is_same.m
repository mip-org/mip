function tf = is_same(a, b)
%IS_SAME   Check whether two absolute paths refer to the same location.
%
% Usage:
%   tf = mip.paths.is_same(a, b)
%
% String comparison after trimming trailing separators; case-insensitive
% on Windows. Does not touch the filesystem.

a = strip_trailing(char(a));
b = strip_trailing(char(b));
if ispc
    tf = strcmpi(a, b);
else
    tf = strcmp(a, b);
end

end

function p = strip_trailing(p)
    while numel(p) > 1 && (p(end) == '/' || (ispc && p(end) == '\'))
        p = p(1:end-1);
    end
end
