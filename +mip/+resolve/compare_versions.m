function result = compare_versions(v1, v2)
%COMPARE_VERSIONS  Compare two version strings.
%
%   result = mip.resolve.compare_versions(v1, v2)
%
%   Returns:
%     1  if v1 > v2
%    -1  if v1 < v2
%     0  if v1 == v2
%
%   Ordering tiers (highest to lowest):
%     1. Numeric versions (compared component-wise on '.', e.g. '1.10' > '1.9')
%     2. 'main'
%     3. 'master'
%     4. Other named versions (alphabetically first ranks higher)
%
%   Any numeric version outranks any non-numeric version.

    n1 = mip.resolve.is_numeric_version(v1);
    n2 = mip.resolve.is_numeric_version(v2);

    if n1 && n2
        result = compareNumeric(v1, v2);
        return
    end

    if n1
        result = 1;
        return
    end
    if n2
        result = -1;
        return
    end

    t1 = namedTier(v1);
    t2 = namedTier(v2);
    if t1 < t2
        result = 1;
        return
    elseif t1 > t2
        result = -1;
        return
    end

    if strcmp(v1, v2)
        result = 0;
    else
        sorted = sort({v1, v2});
        if strcmp(sorted{1}, v1)
            result = 1;
        else
            result = -1;
        end
    end
end

function result = compareNumeric(v1, v2)
    parts1 = str2double(strsplit(v1, '.'));
    parts2 = str2double(strsplit(v2, '.'));

    maxLen = max(length(parts1), length(parts2));
    parts1(end+1:maxLen) = 0;
    parts2(end+1:maxLen) = 0;

    for i = 1:maxLen
        if parts1(i) > parts2(i)
            result = 1;
            return
        elseif parts1(i) < parts2(i)
            result = -1;
            return
        end
    end

    result = 0;
end

function tier = namedTier(v)
    switch v
        case 'main'
            tier = 1;
        case 'master'
            tier = 2;
        otherwise
            tier = 3;
    end
end
