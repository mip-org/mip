function root = root()
%ROOT   Get the mip root directory path.
%
% Usage:
%   root = mip.paths.root()
%
% Returns the path to the mip root directory. If the environment variable
% MIP_ROOT is set to a non-empty value, that value is used. It must point to an
% existing directory containing a 'packages' subdirectory; otherwise an error is
% raised. An empty MIP_ROOT is treated the same as unset.
%
% When MIP_ROOT is unset (or empty), the root is determined from mip's own
% install location (see mip.paths.default_root).
%
% While an environment is active (MEP 8), MIP_ROOT points at that
% environment, so this returns the active environment's root.

root = getenv('MIP_ROOT');
if ~isempty(root)
    if ~isfolder(root)
        error('mip:rootInvalid', ...
            ['MIP_ROOT is set to ''%s'' but that path does not exist ' ...
             'or is not a directory.'], root);
    end
    if ~isfolder(fullfile(root, 'packages'))
        error('mip:rootInvalid', ...
            ['MIP_ROOT is set to ''%s'' but it does not contain a ' ...
             '''packages'' subdirectory.'], root);
    end
    return;
end

root = mip.paths.default_root();

end
