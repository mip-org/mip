function tf = is_env(envPath)
%IS_ENV   Check whether a directory is a mip environment.
%
% Usage:
%   tf = mip.env.is_env(envPath)
%
% A directory is an environment when it contains the mip-env.json marker
% written by "mip env create". The marker is what distinguishes an
% environment from an arbitrary directory: mip activate refuses a
% directory without one, and mip env delete refuses to recursively delete
% one. The global/baseline root has no marker.

tf = isfile(fullfile(envPath, 'mip-env.json'));

end
