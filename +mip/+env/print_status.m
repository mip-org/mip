function print_status()
%PRINT_STATUS   Show the active environment, or that none is active.
%
% Usage:
%   mip env

s = mip.state.get_env_state();
if ~isempty(s)
    fprintf('active environment: %s\n', mip.env.display_env(s));
    return
end

fprintf('no active environment\n');
fprintf('root: %s\n', mip.paths.display_path(mip.paths.root()));
fprintf(['Create an environment with "mip env create <name|path>" and ' ...
         'activate it with "mip activate <name|path>".\n']);

end
