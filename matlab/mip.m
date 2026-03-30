function varargout = mip(command, varargin)
%MIP   A package manager for MATLAB/MEX.
%
% Usage:
%   mip install <package> [...]              - Install one or more packages
%   mip install --channel dev <package>      - Install from a specific channel
%   mip install --channel owner/chan <pkg>   - Install from a user-hosted channel
%   mip install owner/chan/package           - Install using fully qualified name
%   mip update <package> [...]               - Update one or more packages
%   mip update mip                           - Update mip itself
%   mip uninstall <package> [...]            - Uninstall one or more packages
%   mip list                                 - List installed packages
%   mip load <package> [--sticky] [--install] - Load a package into MATLAB path
%   mip unload <package>                     - Unload a package from MATLAB path
%   mip unload --all                         - Unload all non-sticky packages
%   mip unload --all --force                 - Unload all packages (including sticky)
%   mip find-name-collisions                 - Find symbol name collisions
%   mip arch                                 - Display current architecture tag
%   mip info <package>                       - Display package information
%   mip info --channel dev <package>         - Display info from a specific channel
%   mip avail                                - List available packages in repository
%   mip avail --channel dev                  - List packages from a specific channel
%   mip index                                - Display the mip package index URL
%   mip version                              - Display mip version
%   mip help [command]                       - Show help text for command
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
parts = strsplit(mfilename('fullpath'), filesep);
mip_fqn = fullfile(parts{end-4:end-2});
mip.utils.key_value_append('MIP_LOADED_PACKAGES', mip_fqn);
mip.utils.key_value_append('MIP_STICKY_PACKAGES', mip_fqn);

% Normalize command to lowercase
command = lower(command);

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

    case 'uninstall'
        if nargin < 2
            error('mip:noPackage', 'At least one package name required for uninstall command.');
        end
        mip.uninstall(varargin{:});

    case 'list'
        mip.list();

    case 'load'
        if nargin < 2
            error('mip:noPackage', 'No package specified for load command.');
        end
        packageName = varargin{1};
        mip.load(packageName, varargin{2:end});

    case 'unload'
        if nargin < 2
            error('mip:noPackage', 'No package specified for unload command.');
        end
        mip.unload(varargin{:});

    case 'find-name-collisions'
        mip.find_name_collisions();

    case {'architecture', 'arch'}
        fprintf('%s\n', mip.arch());

    case 'info'
        if nargin < 2
            error('mip:noPackage', 'No package specified for info command.');
        end
        mip.info(varargin{:});

    case 'avail'
        mip.avail(varargin{:});

    case 'index'
        [ch, ~] = mip.utils.parse_channel_flag(varargin);
        fprintf('%s\n', mip.index(ch));

    case 'root'
        fprintf('%s\n', mip.root());

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
