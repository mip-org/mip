function env(varargin)
%ENV   Manage mip environments.
%
% Usage:
%   mip env                        - Show the active environment
%   mip env create [name|path]     - Create an empty environment
%   mip env list                   - List named environments
%   mip env delete <name> [--yes]  - Delete a named environment (confirms)
%   mip env activate [name|path]   - Alias for "mip activate"
%   mip env deactivate             - Alias for "mip deactivate"
%
% An environment is a mip root - a directory with a packages/ subtree and
% its own install state, exactly like the global root where mip itself is
% installed - plus the mip-env.json marker written by "mip env create". Session commands
% (install, uninstall, update, load, list, ...) act on the active
% environment, which defaults to the global root when nothing is
% activated.
%
% Environment arguments are disambiguated syntactically: a bare word is a
% name in the central store at <baseline root>/envs/; anything containing
% a path separator is a path (e.g. "mip env create ./.mip"). The
% no-argument "mip env create" creates ./.mip in the current directory.
%
% The "mip env" group manages environments as objects only. Everyday
% operations stay top-level: "mip activate" / "mip deactivate" move the
% session pointer, and "mip install" / "mip uninstall" mutate the active
% environment's contents.

    if isempty(varargin)
        mip.env.show();
        return
    end

    sub = lower(char(varargin{1}));
    rest = varargin(2:end);
    switch sub
        case 'create'
            mip.env.create(rest{:});

        case 'list'
            mip.env.list(rest{:});

        case 'delete'
            mip.env.delete(rest{:});

        case 'activate'
            mip.activate(rest{:});

        case 'deactivate'
            mip.deactivate(rest{:});

        otherwise
            error('mip:unknownSubcommand', ...
                  ['Unknown "mip env" subcommand "%s". ' ...
                   'Use create, list, delete, activate, or deactivate.'], sub);
    end

end
