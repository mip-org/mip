function d = display_path(d)
%DISPLAY_PATH   Format a path for display, shortening $HOME to '~'.

if ~(ispc || isempty(getenv('HOME')))
    d = replace(d, getenv('HOME'), '~');
end

end
