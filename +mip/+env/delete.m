function delete(varargin)
%DELETE   Delete a named mip environment.
%
% Usage:
%   mip env delete <name>
%   mip env delete <name> --yes
%
% The only data-destroying verb in the environment commands: removes the
% environment directory from <baseline root>/envs/ along with everything
% installed in it. Always confirms; --yes skips the prompt, and the
% MIP_CONFIRM environment variable is honored for non-interactive use.
%
% Takes names only: given a path it errors - path environments are
% self-managed, and mip will not recursively delete an arbitrary
% directory it does not own. It also refuses to delete the active
% environment (run "mip deactivate" first) and any directory without the
% mip-env.json marker.

    [opts, args] = mip.parse.flags(varargin, struct('yes', false));

    if isempty(args)
        error('mip:env:noName', ...
              '"mip env delete" requires an environment name.');
    end
    if numel(args) > 1
        error('mip:env:tooManyArgs', ...
              '"mip env delete" takes a single environment name.');
    end

    arg = char(args{1});
    if contains(arg, '/') || (ispc && contains(arg, '\'))
        error('mip:env:pathDelete', ...
              ['"mip env delete" takes a name, not a path. Path environments ' ...
               'are self-managed - delete the directory yourself.']);
    end

    t = mip.env.classify_arg(arg);
    if ~isfolder(t.path)
        error('mip:env:notFound', ...
              'No environment named "%s" in %s.', ...
              t.name, mip.env.display_path(mip.env.store_dir()));
    end
    if ~mip.env.is_env(t.path)
        error('mip:env:notAnEnvironment', ...
              ['"%s" is not a mip environment (no mip-env.json marker); ' ...
               'refusing to delete it.'], t.path);
    end

    active = mip.state.get_active_env();
    if ~isempty(active) && mip.paths.is_same(active.path, t.path)
        error('mip:env:deleteActive', ...
              'Environment "%s" is active. Run "mip deactivate" first.', t.name);
    end

    fprintf('This will delete the environment "%s" and everything installed in it:\n\n', t.name);
    fprintf('  %s\n\n', mip.env.display_path(t.path));
    if opts.yes
        confirm = 'y';
    else
        confirm = getenv('MIP_CONFIRM');
        if isempty(confirm)
            confirm = input('Are you sure? (y/n): ', 's');
        end
    end
    if ~strcmpi(confirm, 'y') && ~strcmpi(confirm, 'yes')
        fprintf('Deletion aborted.\n');
        return
    end

    rmdir(t.path, 's');
    fprintf('Deleted environment "%s"\n', t.name);

end
