function tf = is_local_path(pkg)
%IS_LOCAL_PATH   True if an install argument is a local directory path.
%
% Local paths start with '~', '.', '/', or a Windows drive letter
% (e.g. 'C:\path\mypkg', 'C:/path/mypkg'). Anything else is treated as a
% package name or URL. Purely syntactic — the path need not exist, and
% whether it is actually a directory is checked separately.

if isempty(pkg)
    tf = false;
    return
end
tf = startsWith(pkg, '~') || startsWith(pkg, '.') || startsWith(pkg, '/') || ...
     (length(pkg) >= 3 && isstrprop(pkg(1), 'alpha') && pkg(2) == ':' && ...
      (pkg(3) == '\' || pkg(3) == '/'));

end
