function load_direct()
%LOAD_DIRECT   Load the active root's directly installed packages.
%
% Usage:
%   mip.env.load_direct()
%
% Loads each of the active root's directly installed packages as a
% direct load - dependencies come in transitively, exactly as if the
% user had run "mip load" on each. The load pass behind
% "mip activate --load" and "mip project run". Best-effort: each failure
% prints the mip error, a summary closes the pass, and the root stays
% active regardless.

direct = mip.state.get_directly_installed();
direct = direct(~strcmp(direct, 'gh/mip-org/core/mip'));
if isempty(direct)
    fprintf('No directly installed packages to load.\n');
    return
end

nLoaded = 0;
nFailed = 0;
for i = 1:numel(direct)
    try
        mip.load(direct{i});
        nLoaded = nLoaded + 1;
    catch ME
        nFailed = nFailed + 1;
        fprintf('Failed to load "%s": %s\n', ...
                mip.parse.display_fqn(direct{i}), ME.message);
    end
end
if nFailed > 0
    fprintf('Loaded %d package(s), %d failed.\n', nLoaded, nFailed);
else
    fprintf('Loaded %d package(s).\n', nLoaded);
end

end
