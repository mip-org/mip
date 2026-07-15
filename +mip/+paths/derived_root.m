function root = derived_root()
%DERIVED_ROOT   Root directory the running mip code is installed into, or ''.
%
% Usage:
%   root = mip.paths.derived_root()
%
% Ignores the MIP_ROOT environment variable. Determines the root by
% navigating up from this file's installed location, assuming the layout:
%   <root>/packages/gh/mip-org/core/mip/mip/+mip/+paths/derived_root.m
% Falls back to <userpath>/mip when the layout does not match (e.g. an
% editable install of mip itself, where mfilename resolves to the source
% checkout). Returns '' when neither candidate contains a 'packages'
% subdirectory.

% Navigate up from this file's location:
%   +paths/derived_root -> +paths -> +mip -> mip (source) -> mip (package) -> core -> mip-org -> gh -> packages -> root
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
        root = '';
    end
end

end
