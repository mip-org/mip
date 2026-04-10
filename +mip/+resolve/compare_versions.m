function result = compare_versions(v1, v2)
%COMPARE_VERSIONS  Compare two version strings component-by-component.
%
%   result = mip.resolve.compare_versions(v1, v2)
%
%   Returns:
%     1  if v1 > v2
%    -1  if v1 < v2
%     0  if v1 == v2
%
%   Version strings are split on '.' and compared numerically.
%   Varying component counts are handled by treating missing components as 0.

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
