function tf = is_path(arg)
%IS_PATH   Syntactic name-vs-path disambiguation for an argument.
%
% Usage:
%   tf = mip.parse.is_path(arg)
%
% An argument is a path when it is written explicitly as one ('~', '.',
% '/', or a drive-letter prefix; see mip.parse.is_explicit_path) or when
% it contains a path separator ('/', or '\' on Windows) anywhere — so
% relative paths like 'foo/bar' and '.mip' are both paths. Anything else
% is a name. The two are never guessed between.
%
% Only meaningful for arguments whose names can never contain a
% separator (e.g. environment names). Package arguments use slashes in
% FQNs, so a separator does not mean "path" there; they are categorized
% with mip.parse.is_explicit_path and mip.parse.parse_package_arg
% instead.

if isstring(arg)
    arg = char(arg);
end
tf = mip.parse.is_explicit_path(arg) || contains(arg, '/') || (ispc && contains(arg, '\'));

end
