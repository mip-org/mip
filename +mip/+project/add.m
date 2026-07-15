function add(varargin)
%ADD   Declare project dependencies: edit mip.yaml, re-lock, and sync.
%
% Usage:
%   mip project add <pkg> [...]            - Add to the dependencies list
%   mip project add --dev <pkg> [...]      - Add to the dev group
%   mip project add --group <g> <pkg> ...  - Add to a named group
%   mip project add --no-sync <pkg> [...]  - Edit and re-lock without installing
%
% Edits the nearest mip.yaml's dependency list (see "mip help project"
% for project discovery), re-resolves the lock, and syncs the project
% environment. Entering "add" opts the directory into the declarative
% (uv) mode by creating mip.lock if it does not exist.
%
% Package arguments take the "mip install" channel syntax: bare names,
% FQNs, and @version pins (e.g. chebfun@1.0.0). A package already
% declared in the target list is updated in place, so
% "mip project add chebfun@2.0" re-pins an existing chebfun entry.
% Only channel (GitHub) packages can be declared.
%
% If re-locking fails (e.g. the package is not in any channel), the
% mip.yaml edit is rolled back.

    [opts, args] = mip.parse.flags(varargin, ...
        struct('dev', false, 'group', '', 'no_sync', false, 'directory', ''));
    if isempty(args)
        error('mip:project:noPackage', ...
              'At least one package name is required for "mip project add".');
    end
    group = mip.project.resolve_group_flags(opts);
    validate_package_args(args);

    proj = mip.project.locate(opts.directory);

    prevSpec = fileread(proj.spec_path);
    mip.project.edit_spec(proj.spec_path, group, args, {});
    for i = 1:numel(args)
        fprintf('Added "%s" to %s in mip.yaml\n', args{i}, list_label(group));
    end

    try
        mip.project.lock_project(proj, false);
    catch ME
        restore_spec(proj.spec_path, prevSpec);
        fprintf('Locking failed; mip.yaml restored.\n');
        rethrow(ME);
    end

    if ~opts.no_sync
        syncOpts = struct();
        if ~isempty(group) && ~strcmp(group, 'dev')
            syncOpts.group = {group};
        end
        mip.project.sync_project(proj, syncOpts);
    end

end

function validate_package_args(args)
    for i = 1:numel(args)
        parsed = mip.parse.parse_package_arg(args{i});
        if parsed.is_fqn && ~strcmp(parsed.type, 'gh')
            error('mip:project:unsupportedDependency', ...
                  ['Cannot declare "%s": only channel (GitHub) packages ' ...
                   'can be locked.'], args{i});
        end
    end
end

function label = list_label(group)
    if isempty(group)
        label = 'dependencies';
    else
        label = sprintf('dependency group "%s"', group);
    end
end

function restore_spec(specPath, content)
    fid = fopen(specPath, 'w');
    if fid == -1
        return
    end
    fwrite(fid, content);
    fclose(fid);
end
