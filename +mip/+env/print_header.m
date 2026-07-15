function print_header()
%PRINT_HEADER   Print the "environment:" banner when an environment is active.
%
% Usage:
%   mip.env.print_header()
%
% Called at the top of the commands that mutate or report environment
% contents (install, uninstall, update, list). Prints nothing when no
% environment is active - the global root is a first-class silent
% default target, not a mistake.

env = mip.state.get_active_env();
if isempty(env)
    return
end
fprintf('environment: %s\n', mip.env.describe(env));

end
