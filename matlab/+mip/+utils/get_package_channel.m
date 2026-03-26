function channel = get_package_channel(packageName)
%GET_PACKAGE_CHANNEL   Get the channel a package was installed from.
%
% Args:
%   packageName - Name of the package
%
% Returns:
%   channel - Channel name string, or '' if unknown

channel = '';

filePath = fullfile(mip.utils.get_packages_dir(), 'channel_map.json');
if ~exist(filePath, 'file')
    return
end

try
    channelMap = jsondecode(fileread(filePath));
    if isfield(channelMap, packageName)
        channel = channelMap.(packageName);
    end
catch
    % Ignore errors reading channel map
end

end
