function activate(varargin)
%ACTIVATE   Point the session at an environment (alias for "mip env activate").
%
% Usage:
%   mip activate <name>        - Activate the named env from <baseline root>/envs/
%   mip activate <path>        - Activate the environment at a path
%   mip activate               - Activate ./.mip in the current directory
%   mip activate ... --load    - Also load the env's directly installed packages
%
% See "help mip.env.activate" for details, and "mip deactivate" to return
% to the baseline root.

mip.env.activate(varargin{:});

end
