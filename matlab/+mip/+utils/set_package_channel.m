function set_package_channel(packageName, channel)
%SET_PACKAGE_CHANNEL   Record which channel a package was installed from.
%
% Args:
%   packageName - Name of the package
%   channel     - Channel name (e.g. 'core', 'dev')

channelMap = load_channel_map();
channelMap.(packageName) = channel;
save_channel_map(channelMap);

end


function channelMap = load_channel_map()
    filePath = get_channel_map_path();
    if exist(filePath, 'file')
        jsonText = fileread(filePath);
        channelMap = jsondecode(jsonText);
    else
        channelMap = struct();
    end
end


function save_channel_map(channelMap)
    filePath = get_channel_map_path();
    parentDir = fileparts(filePath);
    if ~exist(parentDir, 'dir')
        mkdir(parentDir);
    end
    jsonText = jsonencode(channelMap);
    fid = fopen(filePath, 'w');
    fwrite(fid, jsonText);
    fclose(fid);
end


function filePath = get_channel_map_path()
    packagesDir = mip.utils.get_packages_dir();
    filePath = fullfile(packagesDir, 'channel_map.json');
end
