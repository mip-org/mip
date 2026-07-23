function tf = is_path(arg)
%IS_PATH   Syntactic name-vs-path disambiguation for an argument.
%
% Usage:
%   tf = mip.parse.is_path(arg)
%
% A bare word is a name; anything containing a path separator ('/', or
% '\' on Windows) is a path. The two are never guessed between.
%
% Only meaningful for arguments whose names can never contain a
% separator (e.g. environment names). Package arguments use slashes in
% FQNs, so a separator does not mean "path" there; they are categorized
% with mip.parse.is_explicit_path and mip.parse.parse_package_arg
% instead.

if isstring(arg)
    arg = char(arg);
end
tf = contains(arg, '/') || (ispc && contains(arg, '\'));

end
