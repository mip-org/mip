function status()
%STATUS   Show the active environment, or that none is active.
%
% Usage:
%   mip env

s = mip.env.active();
if ~isempty(s)
    fprintf('active environment: %s\n', mip.env.describe(s));
    return
end

fprintf('no active environment\n');
fprintf('root: %s\n', mip.paths.display_path(mip.paths.root()));
fprintf(['Create an environment with "mip env create <name|path>" and ' ...
         'activate it with "mip activate <name|path>".\n']);

end
