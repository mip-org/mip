function varargout = mip(command, varargin)
%MIP   A package manager for MATLAB/MEX.
%
% Usage:
%   mip install <package> [...]                - Install one or more packages
%   mip install --channel dev <package>        - Install from a specific channel
%   mip install --channel owner/channel <pkg>  - Install from a user-hosted channel
%   mip install owner/chan/package             - Install using fully qualified name
%   mip update <package> [...]                 - Update one or more packages
%   mip update --force <package>               - Force update even if up to date
%   mip update --deps <package>                - Update package and its dependencies
%   mip update --all                           - Update all installed packages
%   mip update --no-compile <package>          - Skip compile step (editable local installs)
%   mip update mip                             - Update mip itself
%   mip pin <package> [...]                    - Pin packages to their current version
%   mip unpin <package> [...]                  - Unpin packages
%   mip uninstall <package> [...]              - Uninstall one or more packages
%   mip uninstall mip                          - Uninstall mip itself
%   mip list                                   - List installed packages (reverse load order)
%   mip list --sort-by-name                    - List installed packages (alphabetical)
%   mip load <package> [...]  [--sticky]       - Load one or more packages into MATLAB path
%   mip load <package> --addpath <relpath>     - Add a source-relative path after loading
%   mip load <package> --rmpath  <relpath>     - Remove a source-relative path after loading
%   mip load <package> --with <group>          - Also load the named extra path group (e.g. examples, tests)
%   mip unload <package> [...]                 - Unload one or more packages from MATLAB path
%   mip unload --all                           - Unload all non-sticky packages
%   mip unload --all --force                   - Unload all packages (including sticky)
%   mip info                                   - Display info about mip itself
%   mip info <package>                         - Display package information
%   mip info --channel dev <package>           - Display info from a specific channel
%   mip avail                                  - List available packages in repository
%   mip avail --channel dev                    - List packages from a specific channel
%   mip version                                - Display mip version
%   mip test <package>                         - Run package test script
%   mip compile <package>                      - Compile/recompile MEX files
%   mip bundle <directory> [--output <dir>]    - Build .mhl from local package
%   mip init <directory> [--name <name>]       - Generate a starter mip.yaml
%   mip reset                                  - Reset mip to a clean state
%   mip help [command]                         - Show help text for command
%
% Channels:
%   The default channel is 'core' (mip-org/core). Use --channel <name> to
%   install from or query other channels. Channel formats:
%     'core'           -> mip-org/core (default)
%     'dev'            -> mip-org/dev
%     'owner/channel'  -> user-hosted channel
%
% Package names:
%   Packages can be specified by bare name or fully qualified name:
%     mip install chebfun                    - from default channel
%     mip install mip-org/core/chebfun       - fully qualified
%     mip install --channel mylab/custom pkg - from user channel

if nargin < 1
    command = 'help';
end

% Ensure mip itself is always tracked as a loaded sticky package
mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/mip');
mip.state.key_value_append('MIP_STICKY_PACKAGES', 'gh/mip-org/core/mip');

% Normalize command to lowercase
command = lower(command);

% Refresh tab-completion metadata after any command that may have
% changed the installed / loaded / pinned package set. onCleanup
% ensures this fires even if the command errors partway through
% (e.g. `install a b` failing on `b` after `a` succeeded).
if ismember(command, {'install','update','uninstall','load','unload', ...
                     'pin','unpin','reset'})
    refreshSignatures = onCleanup(@safe_update_signatures); %#ok<NASGU>
end

% Handle each command
switch command
    case 'install'
        if nargin < 2
            error('mip:noPackage', 'At least one package name required for install command.');
        end
        mip.install(varargin{:});

    case 'update'
        if nargin < 2
            error('mip:noPackage', 'At least one package name required for update command.');
        end
        mip.update(varargin{:});

    case 'pin'
        if nargin < 2
            error('mip:noPackage', 'At least one package name required for pin command.');
        end
        mip.pin(varargin{:});

    case 'unpin'
        if nargin < 2
            error('mip:noPackage', 'At least one package name required for unpin command.');
        end
        mip.unpin(varargin{:});

    case 'uninstall'
        if nargin < 2
            error('mip:noPackage', 'At least one package name required for uninstall command.');
        end
        mip.uninstall(varargin{:});

    case 'list'
        mip.list(varargin{:});

    case 'load'
        if nargin < 2
            error('mip:noPackage', 'No package specified for load command.');
        end
        mip.load(varargin{:});

    case 'unload'
        if nargin < 2
            error('mip:noPackage', 'No package specified for unload command.');
        end
        mip.unload(varargin{:});

    case 'info'
        mip.info(varargin{:});

    case 'test'
        if nargin < 2
            error('mip:noPackage', 'Package name is required for test command.');
        end
        mip.test(varargin{:});

    case 'compile'
        if nargin < 2
            error('mip:noPackage', 'Package name is required for compile command.');
        end
        mip.compile(varargin{:});

    case 'bundle'
        if nargin < 2
            error('mip:noDirectory', 'A directory path is required for bundle command.');
        end
        mip.bundle(varargin{:});

    case 'init'
        mip.init(varargin{:});

    case 'reset'
        mip.reset();

    case 'avail'
        mip.avail(varargin{:});

    case 'version'
        fprintf('%s\n', mip.version());

    case 'help'
        if nargin > 1
            % Show help text for command
            command = ['+mip/' strrep(varargin{1}, '-', '_') '.m'];
            if ~exist(command, 'file')
                error('mip:unknownCommand', ['Unknown mip command ''' varargin{1} '''.']);
            end
            help(command);
        else
            help mip;
        end

    otherwise
        error('mip:unknownCommand', ...
              'Unknown command "%s". Use "help mip" for usage information.', command);
end

% Return output if requested
if nargout > 0
    varargout{1} = [];
end

end


function safe_update_signatures()
% Wrapped so a write failure never breaks the command the user actually ran.
try
    mip.state.update_function_signatures();
catch
end
end
