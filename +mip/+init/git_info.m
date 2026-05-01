function [repoName, repoUrl] = git_info(targetDir)
%GIT_INFO   Extract a package name and remote URL from .git/config.
%
% Reads <targetDir>/.git/config (if present) and returns the URL of the
% [remote "origin"] (or the first remote in file order if origin is
% absent), plus a repo name derived from the URL. Returns empty strings
% when no .git/config is found, no remote URL is configured, or the
% config cannot be parsed.
%
% The .git/config file is parsed directly rather than shelling out to
% `git`, so this works even when git is not on the PATH.

repoName = '';
repoUrl = '';

configPath = fullfile(char(targetDir), '.git', 'config');
if exist(configPath, 'file') ~= 2
    return;
end

fid = fopen(configPath, 'r');
if fid == -1
    return;
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

% Walk through the INI-style config collecting `url = ...` entries from
% [remote "<name>"] sections. Preserve file order so we can fall back to
% the first-seen remote when origin is absent.
remoteNames = {};
remoteUrls = {};
currentSection = '';
currentRemote = '';
while true
    line = fgetl(fid);
    if ~ischar(line); break; end
    line = strtrim(line);
    if isempty(line) || line(1) == '#' || line(1) == ';'
        continue;
    end

    % Subsection headers like [remote "origin"] — try this first.
    subTok = regexp(line, '^\[(\w+)\s+"([^"]*)"\]$', 'tokens', 'once');
    if ~isempty(subTok)
        currentSection = subTok{1};
        currentRemote = subTok{2};
        continue;
    end
    % Plain section headers like [core].
    secTok = regexp(line, '^\[(\w+)\]$', 'tokens', 'once');
    if ~isempty(secTok)
        currentSection = secTok{1};
        currentRemote = '';
        continue;
    end

    if strcmp(currentSection, 'remote') && ~isempty(currentRemote)
        kvTok = regexp(line, '^(\w+)\s*=\s*(.*)$', 'tokens', 'once');
        if ~isempty(kvTok) && strcmpi(kvTok{1}, 'url')
            remoteNames{end+1} = currentRemote; %#ok<AGROW>
            remoteUrls{end+1} = strtrim(kvTok{2}); %#ok<AGROW>
        end
    end
end

if isempty(remoteUrls)
    return;
end

% Prefer origin; otherwise the first remote seen in file order.
idx = find(strcmp(remoteNames, 'origin'), 1);
if isempty(idx)
    idx = 1;
end
repoUrl = remoteUrls{idx};

% Derive the repo name from the URL: strip a trailing `.git`, then take
% the last segment after splitting on `/` or `:` (handles https,
% ssh://, and git@host:owner/repo forms).
nameSrc = regexprep(repoUrl, '\.git$', '');
parts = regexp(nameSrc, '[/:]', 'split');
parts = parts(~cellfun(@isempty, parts));
if ~isempty(parts)
    repoName = parts{end};
end

end
