function guard = with_root(root)
%WITH_ROOT   Temporarily point mip's install root at a project environment.
%
% Args:
%   root - The project environment root (from mip.env.env_root).
%
% Returns:
%   guard - An onCleanup object. While it is alive, the MIP_ROOT environment
%           variable is set to `root`, so every mip.paths.root() consumer
%           (install, resolve, load, channel cache, state) operates against
%           the project environment instead of the user's global root. When
%           the guard is cleared (e.g. the calling function returns or
%           errors), the previous MIP_ROOT value is restored.
%
% Usage:
%   guard = mip.env.with_root(root); %#ok<NASGU>
%   ... call mip.install / mip.load / etc. scoped to the project ...
%   % guard's onCleanup restores MIP_ROOT when it goes out of scope
%
% This is the single mechanism that redirects the whole package manager at a
% project-local directory, which is why the environment commands can reuse
% the existing install/resolve/load code paths unchanged.

previous = getenv('MIP_ROOT');
setenv('MIP_ROOT', root);
guard = onCleanup(@() setenv('MIP_ROOT', previous));

end
