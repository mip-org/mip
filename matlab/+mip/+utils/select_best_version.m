function bestVersion = select_best_version(versions)
%SELECT_BEST_VERSION   Select the best version from a cell array of version strings.
%
% Priority:
%   1. Highest numeric version (x.y.z where all components are numeric)
%   2. "main" / "master"
%   3. "unspecified"
%   4. Alphabetically first
%
% Args:
%   versions - Cell array of version strings
%
% Returns:
%   bestVersion - The best version string

if isempty(versions)
    bestVersion = '';
    return
end

% Separate numeric and non-numeric versions
numericVersions = {};
for i = 1:length(versions)
    v = versions{i};
    parts = strsplit(v, '.');
    isNumeric = true;
    for j = 1:length(parts)
        if isnan(str2double(parts{j}))
            isNumeric = false;
            break
        end
    end
    if isNumeric
        numericVersions{end+1} = v; %#ok<AGROW>
    end
end

% If there are numeric versions, return the highest one
if ~isempty(numericVersions)
    bestVersion = numericVersions{1};
    for i = 2:length(numericVersions)
        if mip.utils.compare_versions(numericVersions{i}, bestVersion) > 0
            bestVersion = numericVersions{i};
        end
    end
    return
end

% No numeric versions - check for "main"
for i = 1:length(versions)
    if strcmp(versions{i}, 'main')
        bestVersion = 'main';
        return
    end
end

% Check for "master"
for i = 1:length(versions)
    if strcmp(versions{i}, 'master')
        bestVersion = 'master';
        return
    end
end

% Check for "unspecified"
for i = 1:length(versions)
    if strcmp(versions{i}, 'unspecified')
        bestVersion = 'unspecified';
        return
    end
end

% Fall back to alphabetically first
sorted = sort(versions);
bestVersion = sorted{1};

end
