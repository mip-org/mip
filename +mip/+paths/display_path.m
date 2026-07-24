function d = display_path(d)
%DISPLAY_PATH   Shorten a path for display by replacing the home prefix with ~.
%
% Usage:
%   d = mip.paths.display_path(d)
%
% Display-only: never feed the result back into filesystem operations.

home = getenv('HOME');
if ispc || isempty(home)
    return
end
if strcmp(d, home)
    d = '~';
elseif startsWith(d, [home filesep])
    d = ['~' d(length(home)+1:end)];
end

end
