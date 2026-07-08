function p = spec_path(projectDir)
%SPEC_PATH   Path to the environment spec file (mipenv.yaml) in a project.
%
% Args:
%   projectDir - Project directory (from mip.env.project_dir).
%
% Returns:
%   p - <projectDir>/mipenv.yaml

p = fullfile(projectDir, 'mipenv.yaml');

end
