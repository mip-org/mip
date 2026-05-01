function index = fetch_index(channel, forceRefresh)
%FETCH_INDEX   Download and parse the mip package index for a channel.
%
% Args:
%   channel       - Channel spec (e.g., 'mip-org/core'), or empty for default
%   forceRefresh  - Optional logical (default false). If true, bypass the
%                   on-disk cache and always re-download.
%
% Returns:
%   index - Parsed struct from the index JSON
%
% Successful downloads are cached on disk under
% <root>/cache/index/<org>/<channel>.json. The cache entry is reused if it
% is less than CACHE_TTL_SECONDS old, unless forceRefresh is true. Failed
% fetches are not cached.

CACHE_TTL_SECONDS = 30;

if nargin < 2 || isempty(forceRefresh)
    forceRefresh = false;
end

if isempty(channel)
    channel = 'mip-org/core';
end

[org, channelName] = mip.parse.parse_channel_spec(channel);

cacheFile = '';
try
    cacheDir = fullfile(mip.paths.root(), 'cache', 'index', org);
    cacheFile = fullfile(cacheDir, [channelName '.json']);
catch
    % If mip.paths.root() is unavailable, proceed without caching.
end

if ~forceRefresh && ~isempty(cacheFile) && isfile(cacheFile)
    info = dir(cacheFile);
    if ~isempty(info)
        mtime = datetime(info(1).datenum, 'ConvertFrom', 'datenum');
        ageSec = seconds(datetime('now') - mtime);
        if ageSec >= 0 && ageSec < CACHE_TTL_SECONDS
            try
                indexJson = fileread(cacheFile);
                index = parse_index_json(indexJson);
                return
            catch
                % Corrupt cache; fall through to re-fetch.
            end
        end
    end
end

indexUrl = mip.channel.index_url(channel);

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

index = parse_index_json(indexJson);

if ~isempty(cacheFile)
    try
        cacheDir = fileparts(cacheFile);
        if ~isfolder(cacheDir)
            mkdir(cacheDir);
        end
        fid = fopen(cacheFile, 'w');
        if fid ~= -1
            fwrite(fid, indexJson, 'char');
            fclose(fid);
        end
    catch
        % Cache write failure is non-fatal.
    end
end

end


function index = parse_index_json(indexJson)
index = jsondecode(indexJson);
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
