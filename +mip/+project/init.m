function init(varargin)
%INIT   Create a nameless mip.yaml project spec in the current directory.
%
% Usage:
%   mip project init             - Create a mip.yaml project spec here
%   mip project init --from-env  - Seed the dependency list from the
%                                  active environment
%
% Creates a nameless mip.yaml - a project spec with no package identity -
% in the current directory. Like "mip env create", this never walks up
% the directory tree: it creates a project exactly here. The existing
% "mip init" package scaffold is untouched; this is its project-spec
% sibling.
%
% --from-env reads the active environment (the global root when nothing
% is activated) and records its directly installed channel packages as
% the dependency list - names only, with no version pins: the spec
% declares what, and the first "mip project lock" pins exact versions.
% Non-channel installs (local, File Exchange, web), which cannot be
% locked, are skipped with a note.
%
% Creating a spec does not opt the directory into the declarative (uv)
% mode; only creating mip.lock does ("mip project lock", "add", "run").

    [opts, args] = mip.parse.flags(varargin, struct('from_env', false));
    if ~isempty(args)
        error('mip:project:tooManyArgs', '"mip project init" takes no arguments.');
    end

    specPath = fullfile(pwd, 'mip.yaml');
    if isfile(specPath)
        error('mip:project:specExists', ...
              'A mip.yaml already exists in this directory.');
    end

    deps = {};
    if opts.from_env
        deps = deps_from_env();
    end

    lines = {};
    lines{end+1} = '# mip project spec (no package identity - see "mip help project").';
    lines{end+1} = '# "mip project add <pkg>" edits this list; "mip project lock" resolves it';
    lines{end+1} = '# into mip.lock; "mip project sync" materializes ./.mip from the lock.';
    if isempty(deps)
        lines{end+1} = 'dependencies: []';
    else
        lines{end+1} = 'dependencies:';
        for i = 1:numel(deps)
            lines{end+1} = ['  - ' deps{i}]; %#ok<AGROW>
        end
    end

    fid = fopen(specPath, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to %s', specPath);
    end
    fwrite(fid, [strjoin(lines, newline) newline]);
    fclose(fid);

    fprintf('Created mip.yaml (project spec, %d dependenc%s)\n', ...
            numel(deps), pluralIes(numel(deps)));
    fprintf('Next:\n');
    fprintf('  mip project add <package>   declare a dependency (locks and syncs)\n');
    fprintf('  mip project lock            resolve the spec into mip.lock\n');

end

function deps = deps_from_env()
% The active environment's directly installed channel packages, as the
% simplest unambiguous spelling: bare name for mip-org/core packages,
% display FQN otherwise.
    env = mip.state.get_active_env();
    if isempty(env)
        fprintf('No environment is active; reading the global root.\n');
    else
        fprintf('Reading environment: %s\n', mip.env.describe(env));
    end

    deps = {};
    direct = mip.state.get_directly_installed();
    for i = 1:numel(direct)
        fqn = direct{i};
        parsed = mip.parse.parse_package_arg(fqn);
        if ~strcmp(parsed.type, 'gh')
            fprintf('  skipping "%s": non-channel installs cannot be locked\n', ...
                    mip.parse.display_fqn(fqn));
            continue
        end
        if strcmp(parsed.owner, 'mip-org') && strcmp(parsed.channel, 'core')
            deps{end+1} = parsed.name; %#ok<AGROW>
        else
            deps{end+1} = mip.parse.display_fqn(fqn); %#ok<AGROW>
        end
    end
    deps = sort(deps);
end

function s = pluralIes(n)
    if n == 1
        s = 'y';
    else
        s = 'ies';
    end
end
