function cacheFile = writeRepoIndex(rootDir, ownerRepo, entries, githubRepo)
%WRITEREPOINDEX   Write a synthetic package-repository index for tests.
%
% Writes the index of the repository github.com/<owner>/<repo> at the
% cache path used by mip.channel.fetch_index, so installs and updates of
% repository packages read it without network access. Entries have the
% same form as for writeChannelIndex.
%
% Args:
%   rootDir    - The MIP_ROOT directory
%   ownerRepo  - '<owner>/<repo>'
%   entries    - Cell array of entries (see writeChannelIndex)
%   githubRepo - (Optional) github_repo field; defaults to ownerRepo
%
% Returns:
%   cacheFile - Absolute path to the written cache JSON file

if nargin < 4
    githubRepo = ownerRepo;
end
cacheFile = writeChannelIndex(rootDir, ['github.com/' ownerRepo], entries, githubRepo);

end
