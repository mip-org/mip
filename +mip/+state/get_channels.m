function channels = get_channels()
%GET_CHANNELS   Get the list of subscribed channels in priority order.
%
% Returns:
%   channels - Cell array of channel specs (e.g. 'mylab/custom') in
%              priority order (highest priority first). Does NOT include
%              the implicit default 'mip-org/core' channel; that channel
%              is always consulted before any subscribed channel and
%              need not be listed.
%
% Channels are persisted at <root>/packages/channels.txt, one channel
% per line, in stack-like order: the most recently added channel is at
% the END of the file (matching the append semantics of
% MIP_LOADED_PACKAGES). The returned cell array reverses that so the
% highest-priority channel is at index 1.

    channels = {};

    packagesDir = mip.paths.get_packages_dir();
    channelsFile = fullfile(packagesDir, 'channels.txt');

    if ~exist(channelsFile, 'file')
        return
    end

    fid = fopen(channelsFile, 'r');
    if fid == -1
        % File exists (checked above) but cannot be opened. Failing here
        % rather than returning {} avoids set_channels later silently
        % overwriting the file with a one-entry list, dropping the user's
        % prior subscriptions.
        error('mip:fileError', ...
              'Could not read channels file: %s', channelsFile);
    end

    closer = onCleanup(@() fclose(fid));
    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line) && ~isempty(strtrim(line))
            channels{end+1} = strtrim(line); %#ok<AGROW>
        end
    end

    channels = fliplr(channels);
end
