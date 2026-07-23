function tf = is_explicit_path(arg)
%IS_EXPLICIT_PATH   Syntactic test: is this argument written explicitly as a path?
%
% True when the string announces itself as a filesystem path by its
% prefix: '~', '.', '/', or a Windows drive letter (e.g. 'C:\path\mypkg',
% 'C:/path/mypkg'). Purely syntactic — the path need not exist, and
% whether it is actually a directory is checked separately, so callers
% can report errors that match the user's intent.

if isempty(arg)
    tf = false;
    return
end
tf = startsWith(arg, '~') || startsWith(arg, '.') || startsWith(arg, '/') || ...
     (length(arg) >= 3 && isstrprop(arg(1), 'alpha') && arg(2) == ':' && ...
      (arg(3) == '\' || arg(3) == '/'));

end
