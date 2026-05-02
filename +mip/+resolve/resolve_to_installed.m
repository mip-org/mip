function result = resolve_to_installed(packageArg)
%RESOLVE_TO_INSTALLED   Resolve a package argument to an installed package.
%
% Parses the argument (bare name or FQN), resolves bare names among
% installed packages, and verifies the package directory exists.
%
% Args:
%   packageArg - Package string: 'name', 'owner/channel/name', 'local/name',
%                'fex/name', or 'gh/owner/channel/name'.
%
% Returns:
%   result - Struct with fields: fqn, type, owner, channel, name, pkg_dir.
%            Returns empty [] if the package is not installed.

if isstring(packageArg)
    packageArg = char(packageArg);
end

parsed = mip.parse.parse_package_arg(packageArg);

if parsed.is_fqn
    % Canonicalize: find the actual on-disk name (case-insensitive) so that
    % downstream code (and storage) sees the canonical form regardless of
    % how the user typed the name.
    onDisk = mip.resolve.installed_dir(parsed.fqn);
    if isempty(onDisk)
        result = [];
        return
    end
    parsed.name = onDisk;
    if strcmp(parsed.type, 'gh')
        fqn = mip.parse.make_fqn(parsed.owner, parsed.channel, onDisk);
    else
        fqn = [parsed.type '/' onDisk];
    end
    parsed.fqn = fqn;
else
    fqn = mip.resolve.resolve_bare_name(parsed.name);
    if isempty(fqn)
        result = [];
        return
    end
    parsed = mip.parse.parse_package_arg(fqn);
end

pkg_dir = mip.paths.get_package_dir(parsed.fqn);

if ~exist(pkg_dir, 'dir')
    result = [];
    return
end

result = struct( ...
    'fqn', fqn, ...
    'type', parsed.type, ...
    'owner', parsed.owner, ...
    'channel', parsed.channel, ...
    'name', parsed.name, ...
    'pkg_dir', pkg_dir ...
);

end
