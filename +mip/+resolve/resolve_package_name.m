function [owner, channelName, name, version] = resolve_package_name(packageArg, defaultChannel)
%RESOLVE_PACKAGE_NAME   Resolve a package argument to owner/channel/name/version.
%
% Handles both fully qualified names and bare names (with channel context).
% Also extracts an optional @version suffix.
%
% Args:
%   packageArg     - Package string: 'name', 'name@version',
%                    'owner/channel/name', or 'owner/channel/name@version'
%   defaultChannel - Default channel string (e.g. 'mip-org/core', 'owner/channel')
%                    Used when packageArg is a bare name.
%
% Returns:
%   owner       - GitHub repo owner (user or organization)
%   channelName - Channel name
%   name        - Package name
%   version     - Requested version (empty string if not specified)

if nargin < 2 || isempty(defaultChannel)
    defaultChannel = 'mip-org/core';
end

result = mip.parse.parse_package_arg(packageArg);

if result.is_fqn
    if ~strcmp(result.type, 'gh')
        error('mip:invalidPackageSpec', ...
              ['Package "%s" is not a GitHub channel package; only "gh/" ' ...
               'packages can be installed from a channel.'], packageArg);
    end
    owner = result.owner;
    channelName = result.channel;
    name = result.name;
else
    [owner, channelName] = mip.parse.parse_channel_spec(defaultChannel);
    name = result.name;
end

version = result.version;

end
