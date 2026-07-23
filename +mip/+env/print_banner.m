function print_banner()
%PRINT_BANNER   Print the leading "environment:" line when an env is active.
%
% Usage:
%   mip.env.print_banner()
%
% Called by the commands that mutate the environment (install, uninstall,
% update) and by mip list, so their target is visible while an
% environment is active. Prints nothing when no environment is active:
% the global root is a first-class default target, not a mistake.

s = mip.state.get_env_state();
if isempty(s)
    return
end
fprintf('environment: %s\n', mip.env.display_env(s));

end
