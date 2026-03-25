function remove_package_channel(packageName)
%REMOVE_PACKAGE_CHANNEL   Remove channel tracking for an uninstalled package.
%
% Args:
%   packageName - Name of the package

filePath = fullfile(mip.utils.get_packages_dir(), 'channel_map.json');
if ~exist(filePath, 'file')
    return
end

try
    channelMap = jsondecode(fileread(filePath));
    if isfield(channelMap, packageName)
        channelMap = rmfield(channelMap, packageName);
        jsonText = jsonencode(channelMap);
        fid = fopen(filePath, 'w');
        fwrite(fid, jsonText);
        fclose(fid);
    end
catch
    % Ignore errors
end

end
