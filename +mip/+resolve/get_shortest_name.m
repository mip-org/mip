function name = get_shortest_name(fqn)
%GET_SHORTEST_NAME   Return bare name if unique among installed packages, else FQN.
%
% Used to suggest the simplest unambiguous name a user can type.
%
% Args:
%   fqn - Fully qualified package name
%
% Returns:
%   name - Bare name if only one package with that name is installed,
%          otherwise the full FQN

result = mip.parse.parse_package_arg(fqn);
allInstalled = mip.state.list_installed_packages();
count = 0;
for i = 1:length(allInstalled)
    r = mip.parse.parse_package_arg(allInstalled{i});
    if strcmp(r.name, result.name)
        count = count + 1;
    end
end
if count > 1
    name = fqn;
else
    name = result.name;
end

end
