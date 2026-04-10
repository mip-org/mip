function paths = compute_addpaths(baseDir, addpathsConfig)
%COMPUTE_ADDPATHS   Compute resolved path list from addpaths config.
%
% Args:
%   baseDir        - The base directory of the package source
%   addpathsConfig - Cell array of addpath entries from mip.yaml
%                    Each entry is either a struct with .path (and optional
%                    .recursive, .exclude) or a string.
%
% Returns:
%   paths - Cell array of relative path strings (relative to baseDir)

paths = {};

if isempty(addpathsConfig)
    return;
end

if ~iscell(addpathsConfig)
    addpathsConfig = {addpathsConfig};
end

for i = 1:length(addpathsConfig)
    item = addpathsConfig{i};
    if ischar(item)
        paths{end+1} = item; %#ok<AGROW>
    elseif isstruct(item)
        p = item.path;
        if isfield(item, 'recursive') && item.recursive
            exclude = {};
            if isfield(item, 'exclude')
                exclude = item.exclude;
                if ~iscell(exclude)
                    exclude = {exclude};
                end
            end
            fullPath = fullfile(baseDir, p);
            recPaths = findRecursivePaths(fullPath, baseDir, exclude);
            paths = [paths, recPaths]; %#ok<AGROW>
        else
            paths{end+1} = p; %#ok<AGROW>
        end
    end
end

end


function paths = findRecursivePaths(searchDir, baseDir, excludeDirs)
% Recursively find directories containing .m files.
% Returns paths relative to baseDir.

    paths = {};
    if ~exist(searchDir, 'dir')
        return;
    end

    items = dir(searchDir);
    hasMFiles = false;
    for i = 1:length(items)
        if ~items(i).isdir && endsWith(items(i).name, '.m')
            hasMFiles = true;
            break;
        end
    end

    if hasMFiles
        relPath = getRelativePath(searchDir, baseDir);
        paths{end+1} = relPath;
    end

    for i = 1:length(items)
        if items(i).isdir && ~startsWith(items(i).name, '.') && ...
                ~startsWith(items(i).name, '@') && ...
                ~startsWith(items(i).name, '+') && ...
                ~ismember(items(i).name, excludeDirs)
            subPaths = findRecursivePaths( ...
                fullfile(searchDir, items(i).name), baseDir, excludeDirs);
            paths = [paths, subPaths]; %#ok<AGROW>
        end
    end
end


function rel = getRelativePath(targetDir, baseDir)
% Get relative path from baseDir to targetDir.
    targetDir = mip.paths.get_absolute_path(targetDir);
    baseDir   = mip.paths.get_absolute_path(baseDir);
    if strcmp(targetDir, baseDir)
        rel = '.';
    elseif startsWith(targetDir, [baseDir filesep])
        rel = targetDir(length(baseDir) + 2:end);
    else
        rel = targetDir;
    end
end
