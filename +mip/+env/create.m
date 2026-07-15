function create(varargin)
%CREATE   Create an empty mip environment.
%
% Usage:
%   mip env create           - Create ./.mip in the current directory
%   mip env create <name>    - Create <baseline root>/envs/<name>
%   mip env create <path>    - Create the environment at a path
%
% A bare word is a name in the central store; anything containing a path
% separator is a path. The no-argument form acts on ./.mip exactly - it
% never walks up the directory tree.
%
% Creation materializes an empty packages/ subtree and the mip-env.json
% marker file (format version, creation time, creating mip version).
% Everything else in a root (cache, trash, state files) is created lazily
% by the existing machinery, exactly as for the global root.
%
% Creation is strict: an existing environment or a non-empty directory
% that is not an environment is an error - mip will not adopt arbitrary
% directories. The no-argument form additionally errors when a mip.lock
% file is present in the current directory (that directory's .mip is
% managed declaratively by "mip project sync").
%
% A local ./.mip environment should normally be added to the project's
% .gitignore; mip does not edit user files.

    if numel(varargin) > 1
        error('mip:env:tooManyArgs', ...
              '"mip env create" takes at most one argument.');
    end

    if isempty(varargin)
        if isfile(fullfile(pwd, 'mip.lock'))
            error('mip:env:lockfilePresent', ...
                  ['A mip.lock file is present in this directory, so its .mip ' ...
                   'environment is managed declaratively. Run "mip project sync" to ' ...
                   'materialize it instead of "mip env create".']);
        end
        t = struct('kind', 'path', 'name', '', 'path', fullfile(pwd, '.mip'));
        activateHint = 'mip activate';
    else
        t = mip.env.classify_arg(varargin{1});
        if strcmp(t.kind, 'name')
            activateHint = ['mip activate ' t.name];
        else
            activateHint = ['mip activate ' t.path];
        end
    end

    if mip.env.is_env(t.path)
        error('mip:env:alreadyExists', ...
              'Environment already exists: %s', t.path);
    end
    mip.env.materialize(t.path);

    if strcmp(t.kind, 'name')
        fprintf('Created environment "%s" at %s\n', t.name, mip.env.display_path(t.path));
    else
        fprintf('Created environment at %s\n', mip.env.display_path(t.path));
    end
    fprintf('To activate it, run:\n  %s\n', activateHint);

end
