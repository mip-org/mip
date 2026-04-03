function [org, channelName, name, version] = resolve_package_name(packageArg, defaultChannel)
%RESOLVE_PACKAGE_NAME   Resolve a package argument to org/channel/name/version.
%
% Handles both fully qualified names and bare names (with channel context).
% Also extracts an optional @version suffix.
%
% Args:
%   packageArg     - Package string: 'name', 'name@version',
%                    'org/channel/name', or 'org/channel/name@version'
%   defaultChannel - Default channel string (e.g. 'mip-org/core', 'owner/chan')
%                    Used when packageArg is a bare name.
%
% Returns:
%   org         - Organization name
%   channelName - Channel name
%   name        - Package name
%   version     - Requested version (empty string if not specified)

if nargin < 2 || isempty(defaultChannel)
    defaultChannel = 'mip-org/core';
end

result = mip.utils.parse_package_arg(packageArg);

if result.is_fqn
    org = result.org;
    channelName = result.channel;
    name = result.name;
else
    [org, channelName] = mip.utils.parse_channel_spec(defaultChannel);
    name = result.name;
end

version = result.version;

end
