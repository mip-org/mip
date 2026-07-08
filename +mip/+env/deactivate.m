function deactivate(varargin)
%DEACTIVATE   Leave the active project environment for this session.
%
% Usage:
%   mip env deactivate
%
% Unsets MIP_ROOT so mip commands return to operating on the user's global
% root. Packages already added to the MATLAB path stay on it for the rest of
% the session; restart MATLAB for a fully clean slate.

    mip.parse.flags(varargin, struct());
    active = getenv('MIP_ROOT');
    if isempty(active)
        fprintf('No project environment is active.\n');
        return
    end
    setenv('MIP_ROOT', '');
    fprintf('Deactivated project environment (was %s).\n', active);
    fprintf('mip now uses the global root again.\n');
end
