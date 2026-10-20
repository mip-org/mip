function index = fetch_index(channel, forceRefresh)
%FETCH_INDEX   Download and parse a mip package index.
%
% Args:
%   channel       - Index source: a channel spec (e.g. 'mip-org/core'), a
%                   repository 'github.com/<owner>/<repo>' (see
%                   mip.channel.parse_index_source), or empty for default
%   forceRefresh  - Optional logical (default false). If true, bypass the
%                   on-disk cache and always re-download.
%
% Returns:
%   index - Parsed struct from the index JSON
%
% Successful downloads are cached on disk under
% <root>/cache/index/<owner>/<channel>.json for a channel, or
% <root>/cache/repo-index/<owner>/<repo>.json for a repository (kept apart
% because a channel and a repository may share a name). The cache entry is
% reused if it is less than CACHE_TTL_SECONDS old, unless forceRefresh is
% true. Failed fetches are not cached.
%
% A repository whose index download returns HTTP 404 publishes no mip
% package; this raises 'mip:repo:notPublished', so that callers can tell it
% apart from other failures ('mip:indexFetchFailed'). Unlike other
% failures, a 404 is cached (as <repo>.notpublished next to the cache
% entry) for the same TTL, so callers that probe a repository before
% falling back to the personal channel do not repeat the request.
%
% Every load of the mip-org/core index (cached or fresh) also triggers the
% mip self-update notice check (mip.channel.check_mip_update).

CACHE_TTL_SECONDS = 30;

if nargin < 2 || isempty(forceRefresh)
    forceRefresh = false;
end

if isempty(channel)
    channel = 'mip-org/core';
end

[kind, channelOwner, channelName] = mip.channel.parse_index_source(channel);
if strcmp(kind, 'repo')
    cacheSubdir = 'repo-index';
else
    cacheSubdir = 'index';
end

cacheFile = '';
notPublishedFile = '';
try
    cacheDir = fullfile(mip.paths.root(), 'cache', cacheSubdir, channelOwner);
    cacheFile = fullfile(cacheDir, [channelName '.json']);
    if strcmp(kind, 'repo')
        notPublishedFile = fullfile(cacheDir, [channelName '.notpublished']);
    end
catch
    % If mip.paths.root() is unavailable, proceed without caching.
end

indexUrl = mip.channel.index_url(channel);

if ~forceRefresh && is_fresh(cacheFile, CACHE_TTL_SECONDS)
    try
        indexJson = fileread(cacheFile);
        index = parse_index_json(indexJson);
        maybe_check_mip_update(index, kind, channelOwner, channelName);
        return
    catch
        % Corrupt cache; fall through to re-fetch.
    end
end

if ~forceRefresh && is_fresh(notPublishedFile, CACHE_TTL_SECONDS)
    not_published(channelOwner, channelName, indexUrl);
end

tempFile = [tempname, '.json'];
try
    websave(tempFile, indexUrl, weboptions('Timeout', 60));
    indexJson = fileread(tempFile);
    delete(tempFile);
catch ME
    if exist(tempFile, 'file')
        delete(tempFile);
    end
    if strcmp(kind, 'repo') && is_http_404(ME)
        write_cache_file(notPublishedFile, '');
        not_published(channelOwner, channelName, indexUrl);
    end
    error('mip:indexFetchFailed', 'Failed to fetch package index from %s: %s', indexUrl, ME.message);
end

index = parse_index_json(indexJson);
maybe_check_mip_update(index, kind, channelOwner, channelName);

write_cache_file(cacheFile, indexJson);
if isfile(notPublishedFile)
    delete(notPublishedFile);
end

end


function tf = is_fresh(file, ttlSeconds)
% True if file exists and is less than ttlSeconds old.
tf = false;
if isempty(file) || ~isfile(file)
    return
end
info = dir(file);
if isempty(info)
    return
end
mtime = datetime(info(1).datenum, 'ConvertFrom', 'datenum');
ageSec = seconds(datetime('now') - mtime);
tf = ageSec >= 0 && ageSec < ttlSeconds;
end


function write_cache_file(file, content)
if isempty(file)
    return
end
try
    cacheDir = fileparts(file);
    if ~isfolder(cacheDir)
        mkdir(cacheDir);
    end
    fid = fopen(file, 'w');
    if fid ~= -1
        fwrite(fid, content, 'char');
        fclose(fid);
    end
catch
    % Cache write failure is non-fatal.
end
end


function not_published(owner, repo, indexUrl)
error('mip:repo:notPublished', ...
      'github.com/%s/%s does not publish a mip package (no index at %s).', ...
      owner, repo, indexUrl);
end


function maybe_check_mip_update(index, kind, channelOwner, channelName)
% Whenever the core channel index is loaded (cache or network), check
% whether the running mip is outdated and print a self-update notice.
if strcmp(kind, 'channel') && strcmp(channelOwner, 'mip-org') && strcmp(channelName, 'core')
    mip.channel.check_mip_update(index);
end
end


function tf = is_http_404(ME)
% websave reports HTTP status failures with identifiers such as
% 'MATLAB:webservices:HTTP404StatusCodeError'.
tf = contains(ME.identifier, 'HTTP404');
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
