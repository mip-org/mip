function remove(varargin)
%REMOVE   Undeclare project dependencies: edit mip.yaml, re-lock, sync.
%
% Usage:
%   mip project remove <pkg> [...]            - Remove from the dependencies list
%   mip project remove --dev <pkg> [...]      - Remove from the dev group
%   mip project remove --group <g> <pkg> ...  - Remove from a named group
%   mip project remove --no-sync <pkg> [...]  - Edit and re-lock without pruning
%
% Removes entries from the nearest mip.yaml's dependency list (matched
% by package name; @version and channel qualification are ignored),
% re-resolves the lock, and syncs the project environment - which prunes
% the removed packages and their no-longer-needed dependencies. A name
% not declared in the target list is an error.
%
% If re-locking fails, the mip.yaml edit is rolled back.

    [opts, args] = mip.parse.flags(varargin, ...
        struct('dev', false, 'group', '', 'no_sync', false, 'directory', ''));
    if isempty(args)
        error('mip:project:noPackage', ...
              'At least one package name is required for "mip project remove".');
    end
    group = mip.project.resolve_group_flags(opts);

    proj = mip.project.locate(opts.directory);

    prevSpec = fileread(proj.spec_path);
    mip.project.edit_spec(proj.spec_path, group, {}, args);
    for i = 1:numel(args)
        fprintf('Removed "%s" from %s in mip.yaml\n', args{i}, list_label(group));
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
