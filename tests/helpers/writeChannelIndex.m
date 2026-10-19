function cacheFile = writeChannelIndex(rootDir, channel, entries, githubRepo)
%WRITECHANNELINDEX   Write a synthetic channel or repository index for tests.
%
% Writes a fresh-mtime index containing the given packages at the cache
% path used by mip.channel.fetch_index, so install.m / update.m read it
% without network access. See also writeRepoIndex.
%
% Args:
%   rootDir - The MIP_ROOT directory (e.g. tempdir)
%   channel - Index source: a channel spec '<owner>/<channel>' (e.g.
%             'mip-org/core'), or a repository 'github.com/<owner>/<repo>'
%   entries - Cell array of entries. Each element is either:
%             * a char/string package name — shorthand for
%                 version '1.0.0', architecture 'any', no commit hash.
%             * a struct with fields:
%                 .name         (required)
%                 .version      (default '1.0.0')
%                 .architecture (default 'any')
%                 .commit_hash  (optional — field omitted if absent/empty)
%                 .timestamp    (optional — field omitted if absent/empty)
%                 .mhl_url      (default 'https://example.invalid/sentinel.mhl')
%                 .dependencies (default {})
%             Pass {} for an empty index.
%   githubRepo - (Optional) Value of the index's github_repo field; omitted
%                when absent or empty.
%
% Returns:
%   cacheFile - Absolute path to the written cache JSON file

[kind, chOwner, chName] = mip.channel.parse_index_source(channel);
if strcmp(kind, 'repo')
    cacheDir = fullfile(rootDir, 'cache', 'repo-index', chOwner);
else
    cacheDir = fullfile(rootDir, 'cache', 'index', chOwner);
end
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
cacheFile = fullfile(cacheDir, [chName '.json']);

pkgs = cell(1, numel(entries));
for i = 1:numel(entries)
    e = entries{i};
    if ischar(e) || isstring(e)
        e = struct('name', char(e));
    end

    pkg = struct();
    pkg.name = e.name;
    pkg.architecture = fieldOr(e, 'architecture', 'any');
    pkg.version = fieldOr(e, 'version', '1.0.0');
    pkg.mhl_url = fieldOr(e, 'mhl_url', 'https://example.invalid/sentinel.mhl');
    pkg.dependencies = fieldOr(e, 'dependencies', {});
    if isfield(e, 'commit_hash') && ~isempty(e.commit_hash)
        pkg.commit_hash = e.commit_hash;
    end
    if isfield(e, 'timestamp') && ~isempty(e.timestamp)
        pkg.timestamp = e.timestamp;
    end
    pkgs{i} = pkg;
end
indexStruct = struct('packages', {pkgs});
if nargin >= 4 && ~isempty(githubRepo)
    indexStruct.github_repo = githubRepo;
end

fid = fopen(cacheFile, 'w');
fwrite(fid, jsonencode(indexStruct), 'char');
fclose(fid);

end

function v = fieldOr(s, name, default)
if isfield(s, name)
    v = s.(name);
else
    v = default;
end
end
