function cacheFile = writeChannelCache(rootDir, channel, pkgNames)
%WRITECHANNELCACHE   Write a synthetic channel index cache for tests.
%
% Writes a fresh-mtime channel index cache containing the given packages.
% Matches the cache layout used by mip.channel.fetch_index so install.m
% reads it without network access.
%
% Args:
%   rootDir  - The MIP_ROOT directory (e.g. tempdir)
%   channel  - Channel spec in 'org/channel' form (e.g. 'mip-org/core')
%   pkgNames - Cell array of package names; pass {} for an empty index
%
% Returns:
%   cacheFile - Absolute path to the written cache JSON file

parts = strsplit(channel, '/');
org = parts{1};
chName = parts{2};

cacheDir = fullfile(rootDir, 'cache', 'index', org);
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
cacheFile = fullfile(cacheDir, [chName '.json']);

pkgs = cell(1, numel(pkgNames));
for i = 1:numel(pkgNames)
    pkgs{i} = struct( ...
        'name', pkgNames{i}, ...
        'architecture', 'any', ...
        'version', '1.0.0', ...
        'mhl_url', 'https://example.invalid/sentinel.mhl', ...
        'dependencies', {{}});
end
indexStruct = struct('packages', {pkgs});

fid = fopen(cacheFile, 'w');
fwrite(fid, jsonencode(indexStruct), 'char');
fclose(fid);

end
