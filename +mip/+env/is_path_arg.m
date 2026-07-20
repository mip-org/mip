function tf = is_path_arg(arg)
%IS_PATH_ARG   Syntactic name-vs-path disambiguation for env arguments.
%
% Usage:
%   tf = mip.env.is_path_arg(arg)
%
% A bare word is an environment name; anything containing a path
% separator ('/', or '\' on Windows) is a path. The two are never
% guessed between: names resolve only against the baseline envs/ store,
% with no fallback to a local path of the same name.

if isstring(arg)
    arg = char(arg);
end
tf = contains(arg, '/') || (ispc && contains(arg, '\'));

end
