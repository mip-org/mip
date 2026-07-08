function dispatch(varargin)
%DISPATCH   Route a "mip env <subcommand>" call to its handler.
%
% A project environment is a self-contained set of mip packages pinned by a
% lockfile and installed into a project-local directory, so a project can
% declare exactly which MATLAB packages it needs and reproduce them
% elsewhere -- the MATLAB analog of a uv/pip virtual environment.
%
% Files (in the project directory):
%   mipenv.yaml   Hand-authored spec: dependencies + channels.
%   mipenv.lock   Generated lock: resolved versions, URLs, and SHA-256s.
%   .mip/         Project-local install root (isolated from the global one).
%
% Subcommands:
%   mip env init [--directory <dir>] [--name <name>]
%       Create mipenv.yaml and the .mip root.
%   mip env add <package> [...] [--channel <c>] [--no-sync]
%       Add dependencies, re-lock, and install.
%   mip env remove <package> [...] [--no-sync]
%       Remove dependencies, re-lock, and prune.
%   mip env lock [--directory <dir>]
%       Resolve the spec and write mipenv.lock (no install).
%   mip env sync [--directory <dir>] [--relock]
%       Install exactly what mipenv.lock specifies.
%   mip env status [--directory <dir>]
%       Show declared/locked/installed state.
%   mip env activate [--directory <dir>] [--no-load]
%       Point this MATLAB session at the environment and load it.
%   mip env deactivate
%       Return this session to the global root.
%
% All subcommands accept --directory to operate on a project other than the
% current folder (as with "uv --directory"), so a project can hold several
% environments in different subdirectories.

    if nargin < 1
        help('mip.env.dispatch');
        return
    end

    subcommand = lower(char(varargin{1}));
    rest = varargin(2:end);

    switch subcommand
        case 'init'
            mip.env.init(rest{:});
        case 'add'
            mip.env.add(rest{:});
        case 'remove'
            mip.env.remove(rest{:});
        case 'lock'
            mip.env.lock(rest{:});
        case 'sync'
            mip.env.sync(rest{:});
        case 'status'
            mip.env.status(rest{:});
        case 'activate'
            mip.env.activate(rest{:});
        case 'deactivate'
            mip.env.deactivate(rest{:});
        otherwise
            error('mip:env:unknownSubcommand', ...
                  ['Unknown "mip env" subcommand "%s". Valid subcommands: ' ...
                   'init, add, remove, lock, sync, status, activate, ' ...
                   'deactivate.'], subcommand);
    end
end
