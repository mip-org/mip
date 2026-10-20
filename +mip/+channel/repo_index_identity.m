function [owner, name] = repo_index_identity(index, owner, repo)
%REPO_INDEX_IDENTITY   Validate a repository index and return the canonical identity.
%
% A repository publishes exactly one package, whose name must equal the
% repository name up to name equivalence (mip.name.match). GitHub treats
% owner and repository names case-insensitively, so the owner is
% canonicalized to the 'github_repo' field the index carries, which
% prevents the same repository from being installed twice under
% different spellings. The returned name is the package name as the
% index publishes it, which becomes the last component of the FQN
% 'gh/<owner>/<name>'.
%
% Args:
%   index - Parsed index struct (from mip.channel.fetch_index)
%   owner - Owner as given by the user
%   repo  - Repository name as given by the user
%
% Returns:
%   owner - Canonical owner
%   name  - Canonical package name
%
% Errors:
%   mip:repo:invalidIndex - The index publishes no package, more than one
%                           distinct name, or a name that differs from the
%                           repository name.

source = sprintf('github.com/%s/%s', owner, repo);

names = {};
if isfield(index, 'packages')
    pkgs = index.packages;
    for i = 1:length(pkgs)
        if iscell(pkgs)
            pkg = pkgs{i};
        else
            pkg = pkgs(i);
        end
        if isstruct(pkg) && isfield(pkg, 'name') && ...
                ~any(cellfun(@(n) mip.name.match(n, pkg.name), names))
            names{end+1} = pkg.name; %#ok<AGROW>
        end
    end
end

if isempty(names)
    error('mip:repo:invalidIndex', ...
          'The index of %s publishes no package.', source);
end
if numel(names) > 1
    error('mip:repo:invalidIndex', ...
          'The index of %s publishes more than one package (%s).', ...
          source, strjoin(names, ', '));
end
name = names{1};
if ~mip.name.match(name, repo)
    error('mip:repo:invalidIndex', ...
          ['The index of %s publishes the package "%s", whose name does ' ...
           'not match the repository name.'], source, name);
end

if isfield(index, 'github_repo') && ischar(index.github_repo)
    parts = strsplit(index.github_repo, '/');
    if numel(parts) == 2 && strcmpi(parts{1}, owner) && strcmpi(parts{2}, repo)
        owner = parts{1};
    end
end

end
