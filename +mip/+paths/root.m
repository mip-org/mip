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
% When MIP_ROOT is unset (or empty), the root is determined by navigating up
% from this file's installed location, assuming the layout:
%   <root>/packages/gh/mip-org/core/mip/mip/+mip/+paths/root.m

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

root = mip.paths.derived_root();
if isempty(root)
    suggestion = fullfile(userpath, 'mip');
    if ~ispc && ~isempty(getenv('HOME'))
        suggestion = replace(suggestion, getenv('HOME'), '~');
    end
    error('mip:rootNotFound', ...
        ['Could not determine the mip root directory.\n' ...
         'Set the MIP_ROOT environment variable to point to your mip root directory.\n' ...
         'For example: setenv(''MIP_ROOT'', ''%s'')'], suggestion);
end

end
