function project(varargin)
%PROJECT   Declarative, lockfile-driven projects (the mip analog of uv).
%
% Usage:
%   mip project                        - Show project status (alias for status)
%   mip project init [--from-env]      - Create a nameless mip.yaml here
%   mip project add <pkg> [...]        - Edit spec -> re-lock -> sync
%   mip project remove <pkg> [...]     - Edit spec -> re-lock -> sync/prune
%   mip project lock [--upgrade]       - Resolve mip.yaml -> write mip.lock
%   mip project sync                   - Make .mip/ match mip.lock
%   mip project run <target>           - Lock if stale -> sync -> run scoped
%   mip project status [--check]       - Report project, mode, env health, drift
%
% Where "mip install" has you manage an environment by hand (see
% "mip help env"), a project declares its dependencies in mip.yaml - the
% same file that is already the mip package manifest, with package
% identity optional - and mip makes the environment match, pinning the
% resolved closure in mip.lock so any machine rebuilds it identically.
% mip.yaml and mip.lock are committed; .mip/ is a disposable copy of the
% lock and belongs in .gitignore.
%
% The switch between the hand-managed mode and this declarative one is a
% single observable fact: does mip.lock exist? "mip project lock", "add",
% and "run" each create the lock and thereby opt the directory in;
% committing the lock opts in the whole team. In the declarative mode,
% "mip install" still works but its additions are temporary - unrecorded
% in the lock and removed by the next "mip project sync".
%
% Project commands act on the nearest mip.yaml, found by walking up from
% the current directory (as git finds .git); --directory <dir> overrides
% the starting point, and the first output line announces the target.
% Session commands (install, load, list, ...) never walk - they act on
% the active environment. Only "mip project init" creates a project
% exactly where it is run.
%
% mip.yaml gains two project-only keys, stripped from the published
% mip.json: dependency_groups (named extra dependency lists; "dev" is
% conventional, installed by "sync" and "run" by default) and channels
% (extra channels beyond mip-org/core, consulted at lock time).
%
% See the help of each subcommand for details, e.g. "help mip.project.run".

    if isempty(varargin)
        mip.project.status();
        return
    end

    sub = lower(char(varargin{1}));
    rest = varargin(2:end);
    switch sub
        case 'init'
            mip.project.init(rest{:});

        case 'add'
            mip.project.add(rest{:});

        case 'remove'
            mip.project.remove(rest{:});

        case 'lock'
            mip.project.lock(rest{:});

        case 'sync'
            mip.project.sync(rest{:});

        case 'run'
            mip.project.run(rest{:});

        case 'status'
            mip.project.status(rest{:});

        otherwise
            error('mip:unknownSubcommand', ...
                  ['Unknown "mip project" subcommand "%s". ' ...
                   'Use init, add, remove, lock, sync, run, or status.'], sub);
    end

end
