function root = env_root(projectDir, create)
%ENV_ROOT   Path to a project's local mip install root (its ".mip" dir).
%
% Args:
%   projectDir - Project directory (from mip.env.project_dir).
%   create     - (Optional, default false) If true, create the root and its
%                "packages" subdirectory so mip.paths.root() accepts it as a
%                valid MIP_ROOT.
%
% Returns:
%   root - <projectDir>/.mip
%
% A project environment reuses mip's normal install machinery by pointing
% MIP_ROOT at this directory (see mip.env.with_root). Everything mip
% installs for the project -- the packages tree, the index cache, and the
% per-project directly_installed.txt state -- lives here, isolated from the
% user's global mip root.

if nargin < 2
    create = false;
end

root = fullfile(projectDir, '.mip');

if create
    pkgsDir = fullfile(root, 'packages');
    if exist(pkgsDir, 'dir') ~= 7
        [ok, msg] = mkdir(pkgsDir);
        if ~ok
            error('mip:env:rootCreateFailed', ...
                  'Could not create project environment root at "%s": %s', ...
                  root, msg);
        end
    end
end

end
