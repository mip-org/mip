function result = resolve_to_installed(packageArg)
%RESOLVE_TO_INSTALLED   Resolve a package argument to an installed package.
%
% Parses the argument (bare name or FQN), resolves bare names among
% installed packages, and verifies the package directory exists.
%
% Args:
%   packageArg - Package string: 'name' or 'org/channel/name'
%
% Returns:
%   result - Struct with fields: fqn, org, channel, name, pkg_dir
%            Returns empty [] if the package is not installed.

if isstring(packageArg)
    packageArg = char(packageArg);
end

parsed = mip.utils.parse_package_arg(packageArg);

if parsed.is_fqn
    fqn = packageArg;
else
    fqn = mip.utils.resolve_bare_name(parsed.name);
    if isempty(fqn)
        result = [];
        return
    end
    parsed = mip.utils.parse_package_arg(fqn);
end

pkg_dir = mip.utils.get_package_dir(parsed.org, parsed.channel, parsed.name);

if ~exist(pkg_dir, 'dir')
    result = [];
    return
end

result = struct( ...
    'fqn', fqn, ...
    'org', parsed.org, ...
    'channel', parsed.channel, ...
    'name', parsed.name, ...
    'pkg_dir', pkg_dir ...
);

end
