function root = root()
%ROOT   Get the mip root directory path.
%   ROOT() returns the path to the mip root directory. If the environment
%   variable MIP_ROOT is set to a non-empty value, that value is used. It
%   must point to an existing directory containing a 'packages'
%   subdirectory; otherwise an error is raised. An empty MIP_ROOT is
%   treated the same as unset.
%
%   When MIP_ROOT is unset (or empty), the root is determined by navigating
%   up from this file's installed location, assuming the layout:
%     <root>/packages/mip-org/core/mip/mip/+mip/root.m

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

% Navigate up from this file's location:
%   +mip/root -> +mip -> mip (source) -> mip (package) -> core -> mip-org -> packages -> root
this_dir     = fileparts(mfilename('fullpath')); % .../+mip
source_dir   = fileparts(this_dir);              % .../mip/mip
package_dir  = fileparts(source_dir);            % .../core/mip
channel_dir  = fileparts(package_dir);           % .../mip-org/core
org_dir      = fileparts(channel_dir);           % .../packages/mip-org
packages_dir = fileparts(org_dir);               % .../packages
root         = fileparts(packages_dir);          % .../root

if ~isfolder(fullfile(root, 'packages'))
    % Path-based detection failed (e.g., editable install where
    % mfilename returns the source path). Fall back to <userpath>/mip.
    root = fullfile(userpath, 'mip');
    if ~isfolder(fullfile(root, 'packages'))
        if ~ispc && ~isempty(getenv('HOME'))
            root = replace(root, getenv('HOME'), '~');
        end
        error('mip:rootNotFound', ...
            ['Could not determine the mip root directory.\n' ...
             'Set the MIP_ROOT environment variable to point to your mip root directory.\n' ...
             'For example: setenv(''MIP_ROOT'', ''%s'')'], root);
    end
end

end
