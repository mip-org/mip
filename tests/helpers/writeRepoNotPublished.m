function markerFile = writeRepoNotPublished(rootDir, ownerRepo)
%WRITEREPONOTPUBLISHED   Mark a repository as publishing no mip package.
%
% Writes the fresh-mtime marker that mip.channel.fetch_index leaves after
% a 404 for the repository's index, so fetch_index raises
% mip:repo:notPublished for github.com/<owner>/<repo> without network
% access. See also writeRepoIndex.
%
% Args:
%   rootDir   - The MIP_ROOT directory
%   ownerRepo - '<owner>/<repo>'
%
% Returns:
%   markerFile - Absolute path to the written marker file

parts = strsplit(ownerRepo, '/');
cacheDir = fullfile(rootDir, 'cache', 'repo-index', parts{1});
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
markerFile = fullfile(cacheDir, [parts{2} '.notpublished']);
fid = fopen(markerFile, 'w');
fclose(fid);

end
