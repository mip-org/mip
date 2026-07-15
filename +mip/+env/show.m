function show()
%SHOW   Report the active environment (or that none is active).
%
% Usage:
%   mip env

    env = mip.state.get_active_env();
    if isempty(env)
        fprintf('No environment is active. Commands target: %s\n', ...
                mip.env.display_path(mip.paths.root()));
        fprintf(['Create an environment with "mip env create <name>" and ' ...
                 'activate it with "mip activate <name>".\n']);
        return
    end
    fprintf('active environment: %s\n', mip.env.describe(env));

end
