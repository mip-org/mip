function varargout = mip(command, varargin)
%MIP   A package manager for MATLAB/MEX.
%
% Usage:
%   mip install <package> [...]              - Install one or more packages
%   mip install --channel dev <package>      - Install from a specific channel
%   mip uninstall <package> [...]            - Uninstall one or more packages
%   mip list                                 - List installed packages
%   mip load <package> [--sticky]            - Load a package into MATLAB path
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
%   The default channel is 'core'. Use --channel <name> to install from or
%   query other channels (e.g., 'dev' for development/staging packages).

if nargin < 1
    command = 'help';
end

% Normalize command to lowercase
command = lower(command);

% Handle each command
switch command
    case 'install'
        if nargin < 2
            error('mip:noPackage', 'At least one package name required for install command.');
        end
        mip.install(varargin{:});

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
