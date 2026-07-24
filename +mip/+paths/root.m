function root = root(kind)
%ROOT   Get the mip root directory path.
%
% Usage:
%   root = mip.paths.root()            - Same as 'active'
%   root = mip.paths.root('active')    - The root session commands currently act on
%   root = mip.paths.root('base')      - The root the session would use with no environment active
%   root = mip.paths.root('derived')   - The root derived from mip's own install location
%
% Returns the path to the mip root directory. The kinds form a ladder, each
% honoring one less layer of session context:
%
%   'active'  - The root session commands currently act on: MIP_ROOT if set to a
%               non-empty value, otherwise the root derived from mip's own
%               install location.  While an environment is active, MIP_ROOT
%               points at that environment, so this returns the active
%               environment's root. If MIP_ROOT is non-empty, it must point to
%               an existing directory containing a 'packages' subdirectory;
%               otherwise an error is raised. An empty MIP_ROOT is treated the
%               same as unset.
%
%   'base'    - The root the session would use if no environment were active:
%               identical to the 'active' root when no environment is active.
%               While an environment is active this returns the saved
%               pre-activation root. Activating an environment never changes the
%               base root: deactivating an environment returns to it and the
%               named-environment store (<base root>/envs/) lives inside it, so
%               named-env operations resolve against the same store regardless
%               of which environment is active.
%
%   'derived' - The root derived from mip's own install location, ignoring
%               MIP_ROOT entirely. This is what 'active' and 'base' fall back to
%               when MIP_ROOT is unset, determined by navigating up from this
%               file's installed location assuming the layout:
%                 <derived root>/packages/gh/mip-org/core/mip/mip/+mip/+paths/root.m
%               with <userpath>/mip as a fallback (since the installed layout
%               does not hold for an editable source checkout).
%               Errors if no root can be determined this way. Note this is not
%               necessarily "the root mip runs from" (see mip.self.is_own_root).

if nargin < 1
    kind = 'active';
end
if isstring(kind)
    kind = char(kind);
end

switch kind
    case 'active'
        root = active_root();
    case 'base'
        root = base_root();
    case 'derived'
        root = derived_root();
    otherwise
        error('mip:invalidRootKind', ...
              ['Unknown root kind "%s". Valid kinds are ''active'' ' ...
               '(the default), ''base'', and ''derived''.'], kind);
end

end

function root = active_root()
% MIP_ROOT if set (validated), else the derived root.
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

    root = derived_root();
end

function root = base_root()
% The saved pre-activation MIP_ROOT while an environment is active;
% identical to the active root otherwise.
    s = mip.state.get_env_state();
    if isempty(s)
        root = active_root();
        return
    end

    root = s.saved_mip_root;
    if isempty(root)
        root = derived_root();
        return
    end

    % Validate the saved external root the same way the 'active' kind
    % validates MIP_ROOT.
    if ~mip.paths.is_valid_root(root)
        error('mip:rootInvalid', ...
            ['The base root ''%s'' (the MIP_ROOT value saved at ' ...
             'activation) does not exist or does not contain a ' ...
             '''packages'' subdirectory.'], root);
    end
end

function root = derived_root()
% Navigate up from this file's location:
%   +paths/root -> +paths -> +mip -> mip (source) -> mip (package) -> core -> mip-org -> gh -> packages -> root
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
