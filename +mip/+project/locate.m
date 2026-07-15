function proj = locate(directory, announce)
%LOCATE   Resolve the project a "mip project" command acts on.
%
% Usage:
%   proj = mip.project.locate()                    - walk up from pwd
%   proj = mip.project.locate(directory)           - walk up from directory
%   proj = mip.project.locate(directory, announce) - control the announce line
%
% Project commands act on the nearest mip.yaml, found by walking up from
% the starting directory the way git finds .git and cargo finds
% Cargo.toml. The innermost spec wins; the walk stops at the home
% directory (which is itself checked) and at filesystem boundaries.
% Activation state is ignored - only the committed, user-owned mip.yaml
% is ever discovered by walking, never mutable environment state.
%
% The first output line announces the target ("using project at ...")
% unless announce is false.
%
% Args:
%   directory - Starting directory ('' or omitted: the current directory).
%               This is the --directory override on the project commands.
%   announce  - (Optional) Print the "using project at ..." line.
%               Default true.
%
% Returns:
%   proj - Struct with fields:
%     dir       - Absolute path of the project directory
%     spec_path - <dir>/mip.yaml
%     lock_path - <dir>/mip.lock
%     env_path  - <dir>/.mip
%
% Errors mip:project:notFound when no mip.yaml exists on the walk.

if nargin < 1
    directory = '';
end
if nargin < 2
    announce = true;
end

if isempty(directory)
    startDir = pwd;
else
    if ~isfolder(directory)
        error('mip:project:directoryNotFound', ...
              '--directory "%s" does not exist or is not a directory.', ...
              directory);
    end
    startDir = mip.paths.get_absolute_path(directory);
end

projectDir = mip.project.find_dir(startDir);
if isempty(projectDir)
    error('mip:project:notFound', ...
          ['No mip.yaml found walking up from "%s".\n' ...
           'Create a project spec here with:\n  mip project init'], ...
          mip.env.display_path(startDir));
end

proj = struct( ...
    'dir',       projectDir, ...
    'spec_path', fullfile(projectDir, 'mip.yaml'), ...
    'lock_path', fullfile(projectDir, 'mip.lock'), ...
    'env_path',  fullfile(projectDir, '.mip'));

if announce
    fprintf('using project at %s (mip.yaml)\n', mip.env.display_path(projectDir));
end

end
