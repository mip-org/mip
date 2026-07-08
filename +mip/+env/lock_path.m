function p = lock_path(projectDir)
%LOCK_PATH   Path to the environment lock file (mipenv.lock) in a project.
%
% Args:
%   projectDir - Project directory (from mip.env.project_dir).
%
% Returns:
%   p - <projectDir>/mipenv.lock
%
% The lock file's content is JSON (MATLAB parses/emits JSON natively via
% jsondecode/jsonencode); the ".lock" extension mirrors uv.lock and marks
% the file as generated, not hand-edited.

p = fullfile(projectDir, 'mipenv.lock');

end
