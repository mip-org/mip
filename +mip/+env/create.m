function create(varargin)
%CREATE   Create an empty mip environment.
%
% Usage:
%   mip env create              - Create ./.mip in the current directory
%   mip env create <name>       - Create <baseline root>/envs/<name>
%   mip env create <path>       - Create the given directory
%
% A bare word is a name in the central store; anything containing a path
% separator is a path. Creation materializes exactly one thing: an empty
% packages/ subtree, which is what makes the directory an environment
% (the same signal mip.paths.root keys on). Everything else in a root is
% created lazily by the existing machinery.
%
% Creation is strict:
%   - target is already an environment           -> error
%   - target is a non-empty non-environment dir  -> error
%   - target is empty or does not exist          -> created
% The no-argument form additionally errors if a mip.lock file is present
% in the current directory (that directory is managed declaratively; its
% ./.mip is derived from the lockfile, not created by hand).
%
% A local ./.mip environment should normally be added to the project's
% .gitignore; mip does not edit user files.

[~, args] = mip.parse.flags(varargin, struct());

if length(args) > 1
    error('mip:env:tooManyArgs', ...
          '"mip env create" takes at most one name or path argument.');
end

if isempty(args)
    if isfile(fullfile(pwd, 'mip.lock'))
        error('mip:env:lockfilePresent', ...
              ['This directory has a mip.lock file, so its ./.mip ' ...
               'environment is derived from the lockfile (declarative ' ...
               'mode), not created by hand.']);
    end
    target = fullfile(pwd, '.mip');
    activateHint = 'mip activate';
else
    arg = char(args{1});
    if mip.env.is_path_arg(arg)
        target = arg;
        activateHint = sprintf('mip activate %s', arg);
    else
        if ~mip.name.is_valid(arg)
            error('mip:env:invalidName', ...
                  ['Invalid environment name "%s". Names may contain ' ...
                   'letters, digits, hyphens, and underscores, and must ' ...
                   'start and end with a letter or digit. To create an ' ...
                   'environment at a path, include a path separator ' ...
                   '(e.g. ./%s).'], arg, arg);
        end
        target = fullfile(mip.env.store_dir(), arg);
        activateHint = sprintf('mip activate %s', arg);
    end
end

if mip.paths.is_root(target)
    error('mip:env:alreadyExists', ...
          'Environment already exists: %s', target);
end

if isfolder(target) && ~dir_is_empty(target)
    error('mip:env:directoryNotEmpty', ...
          ['"%s" exists and is not empty; mip will not adopt an ' ...
           'arbitrary directory as an environment.'], target);
end

[ok, msg] = mkdir(fullfile(target, 'packages'));
if ~ok
    error('mip:env:createFailed', ...
          'Could not create environment at "%s": %s', target, msg);
end

targetAbs = mip.paths.get_absolute_path(target);
fprintf('Created environment: %s\n', mip.paths.display_path(targetAbs));
fprintf('To activate it, run:\n  %s\n', activateHint);

end

function tf = dir_is_empty(d)
    entries = dir(d);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    tf = isempty(entries);
end
