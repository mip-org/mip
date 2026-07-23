function delete(varargin)
%DELETE   Delete a named environment from the central store.
%
% Usage:
%   mip env delete <name>
%   mip env delete <name> --yes
%
% The only data-destroying verb in the env group; always confirms before
% deleting (--yes skips, and the MIP_CONFIRM environment variable is
% honored for non-interactive use). Takes names only: path environments
% are self-managed, so mip will not recursively delete an arbitrary
% directory it does not own. Refuses to delete the active environment
% and refuses a directory that is not a mip environment (no packages/
% subtree).

[opts, args] = mip.parse.flags(varargin, struct('yes', false));

if isempty(args)
    error('mip:env:nameRequired', ...
          '"mip env delete" requires an environment name.');
end
if length(args) > 1
    error('mip:env:tooManyArgs', ...
          '"mip env delete" takes a single environment name.');
end

arg = char(args{1});
if mip.parse.is_path(arg)
    error('mip:env:pathDelete', ...
          ['Path environments are self-managed — delete the directory ' ...
           'yourself.']);
end
if ~mip.name.is_valid(arg)
    error('mip:env:invalidName', ...
          ['Invalid environment name "%s". Names may contain letters, ' ...
           'digits, hyphens, and underscores, and must start and end ' ...
           'with a letter or digit.'], arg);
end

target = fullfile(mip.paths.get_envs_dir(), arg);
if ~isfolder(target)
    error('mip:env:notFound', ...
          'No environment named "%s". Run "mip env list" to see named environments.', arg);
end
if ~mip.paths.is_valid_root(target)
    error('mip:env:notAnEnvironment', ...
          ['"%s" is not a mip environment (it has no packages/ ' ...
           'subtree); not deleting it.'], target);
end

targetAbs = mip.paths.get_absolute_path(target);

s = mip.state.get_env_state();
if ~isempty(s) && strcmp(s.root, targetAbs)
    error('mip:env:deleteActive', ...
          'Environment "%s" is active. Run "mip deactivate" first.', arg);
end

if ~opts.yes
    confirm = getenv('MIP_CONFIRM');
    if isempty(confirm)
        confirm = input(sprintf('Delete environment "%s" (%s)? (y/n): ', ...
                                arg, mip.paths.display_path(targetAbs)), 's');
    end
    if ~strcmpi(confirm, 'y') && ~strcmpi(confirm, 'yes')
        fprintf('Deletion aborted.\n');
        return
    end
end

rmdir(targetAbs, 's');
fprintf('Deleted environment "%s"\n', arg);

end
