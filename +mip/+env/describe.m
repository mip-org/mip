function d = describe(s)
%DESCRIBE   One-line display form of an environment state struct.
%
% Usage:
%   d = mip.env.describe(s)
%
% Named envs display as 'name (path)'; path envs as the path alone.

p = mip.paths.display_path(s.root);
if isempty(s.name)
    d = p;
else
    d = sprintf('%s (%s)', s.name, p);
end

end
