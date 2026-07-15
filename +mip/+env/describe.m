function s = describe(env)
%DESCRIBE   One-line display form of an environment.
%
% Usage:
%   s = mip.env.describe(env)
%
% Named environments render as 'name (path)'; path environments as the
% path alone. env is a struct with fields 'name' and 'path' (e.g. from
% mip.state.get_active_env).

p = mip.env.display_path(env.path);
if isempty(env.name)
    s = p;
else
    s = sprintf('%s (%s)', env.name, p);
end

end
