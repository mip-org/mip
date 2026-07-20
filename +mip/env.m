function env(varargin)
%ENV   Manage mip environments.
%
% An environment is a mip root — a directory with a packages/ subtree,
% exactly like the global root — that the session can point its commands
% at. Environments come in three kinds: the global root (where mip is
% installed; the default), named environments in the central store
% (<baseline root>/envs/<name>), and local path environments (./.mip,
% or any directory you choose).
%
% Usage:
%   mip env                        - Show the active environment
%   mip env create [name|path]     - Create an empty environment
%                                    (no argument: ./.mip in the current directory)
%   mip env list                   - List named environments
%   mip env delete <name> [--yes]  - Delete a named environment (confirms)
%   mip env activate [name|path] [--load]
%                                  - Point the session at an environment
%                                    (alias: mip activate)
%   mip env deactivate             - Point the session back at the baseline root
%                                    (alias: mip deactivate)
%
% A bare word is an environment name, resolved in the central store only;
% anything containing a path separator is a path. Named environments are
% inventoried by mip (mip env list); path environments are the user's to
% manage like any other directory.
%
% Session commands (install, uninstall, update, load, list, ...) act on
% the active environment — the global root when none is active — and
% never discover environments from the filesystem. While an environment
% is active, the mutating commands print a leading "environment:" line.
%
% In the shell CLI, activation does not exist; target a specific root by
% setting the MIP_ROOT environment variable instead.

if isempty(varargin)
    mip.env.status();
    return
end

sub = varargin{1};
if isstring(sub)
    sub = char(sub);
end
sub = lower(sub);

switch sub
    case 'create'
        mip.env.create(varargin{2:end});
    case 'list'
        mip.env.list(varargin{2:end});
    case 'delete'
        mip.env.delete(varargin{2:end});
    case 'activate'
        mip.env.activate(varargin{2:end});
    case 'deactivate'
        mip.env.deactivate(varargin{2:end});
    otherwise
        error('mip:unknownSubcommand', ...
              ['Unknown "mip env" subcommand "%s". Use create, list, ' ...
               'delete, activate, or deactivate.'], sub);
end

end
