function deactivate(varargin)
%DEACTIVATE   Point the session back at the base root (alias for "mip env deactivate").
%
% Usage:
%   mip deactivate
%
% Restores the pre-activation session: MIP_ROOT (which may be an
% externally set custom root, or unset) and the previously loaded
% package set. See "help mip.env.deactivate" for details.

mip.env.deactivate(varargin{:});

end
