function index = fetch_index(channel)
%FETCH_INDEX   Download and parse the mip package index for a channel.
%
% Args:
%   channel - Channel name (e.g., 'core', 'dev'), or empty for default
%
% Returns:
%   index - Parsed struct from the index JSON

indexUrl = mip.index(channel);

tempFile = [tempname, '.json'];
try
    websave(tempFile, indexUrl);
    indexJson = fileread(tempFile);
    delete(tempFile);
catch ME
    if exist(tempFile, 'file')
        delete(tempFile);
    end
    error('mip:indexFetchFailed', 'Failed to fetch package index from %s: %s', indexUrl, ME.message);
end

index = jsondecode(indexJson);

end
