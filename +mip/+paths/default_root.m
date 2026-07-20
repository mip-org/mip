function root = default_root()
%DEFAULT_ROOT   The mip root derived from mip's own install location.
%
% Usage:
%   root = mip.paths.default_root()
%
% Ignores the MIP_ROOT environment variable entirely; this is the root
% mip.paths.root() falls back to when MIP_ROOT is unset, determined by
% navigating up from this file's installed location, assuming the layout:
%   <root>/packages/gh/mip-org/core/mip/mip/+mip/+paths/default_root.m
%
% Errors with mip:rootNotFound if no root can be determined this way.

% Navigate up from this file's location:
%   +paths/default_root -> +paths -> +mip -> mip (source) -> mip (package) -> core -> mip-org -> gh -> packages -> root
this_dir     = fileparts(mfilename('fullpath')); % .../+paths
mip_dir      = fileparts(this_dir);              % .../+mip
source_dir   = fileparts(mip_dir);               % .../mip/mip
package_dir  = fileparts(source_dir);            % .../core/mip
channel_dir  = fileparts(package_dir);           % .../mip-org/core
owner_dir    = fileparts(channel_dir);           % .../gh/mip-org
gh_dir       = fileparts(owner_dir);             % .../packages/gh
packages_dir = fileparts(gh_dir);                % .../packages
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
