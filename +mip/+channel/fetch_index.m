function index = fetch_index(channel)
%FETCH_INDEX   Download and parse the mip package index for a channel.
%
% Args:
%   channel - Channel spec (e.g., 'mip-org/core'), or empty for default
%
% Returns:
%   index - Parsed struct from the index JSON

indexUrl = mip.index(channel);

tempFile = [tempname, '.json'];
try
    websave(tempFile, indexUrl, weboptions('Timeout', 60));
    indexJson = fileread(tempFile);
    delete(tempFile);
catch ME
    if exist(tempFile, 'file')
        delete(tempFile);
    end
    error('mip:indexFetchFailed', 'Failed to fetch package index from %s: %s', indexUrl, ME.message);
end

index = jsondecode(indexJson);

% Normalize fields that jsondecode may not return as cell arrays
if isfield(index, 'packages')
    if ~iscell(index.packages)
        index.packages = num2cell(index.packages);
    end
    for i = 1:length(index.packages)
        if ~isfield(index.packages{i}, 'dependencies')
            index.packages{i}.dependencies = {};
        elseif isempty(index.packages{i}.dependencies)
            index.packages{i}.dependencies = {};
        elseif ~iscell(index.packages{i}.dependencies)
            index.packages{i}.dependencies = {index.packages{i}.dependencies};
        end
    end
end

end
