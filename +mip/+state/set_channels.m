function set_channels(channels)
%SET_CHANNELS   Set the subscribed channel list (atomic write).
%
% Args:
%   channels - Cell array of channel specs in priority order (highest
%              priority first). Each entry must be in 'org/channel' form;
%              callers are responsible for normalizing shorthand inputs.

    packagesDir = mip.paths.get_packages_dir();

    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    channelsFile = fullfile(packagesDir, 'channels.txt');
    tmpFile = [channelsFile '.tmp'];

    fid = fopen(tmpFile, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to channels.txt.tmp');
    end

    try
        for i = 1:length(channels)
            fprintf(fid, '%s\n', channels{i});
        end
        fclose(fid);
    catch ME
        fclose(fid);
        if exist(tmpFile, 'file')
            delete(tmpFile);
        end
        rethrow(ME);
    end

    [ok, msg] = movefile(tmpFile, channelsFile, 'f');
    if ~ok
        if exist(tmpFile, 'file')
            delete(tmpFile);
        end
        error('mip:fileError', 'Could not rename tmp file into place: %s', msg);
    end
end
