function tf = is_numeric_version(v)
%IS_NUMERIC_VERSION   True when v is a dot-separated sequence of numeric
%components (e.g. '1', '0.5.0'). Used by version-selection code to
%distinguish numeric releases from branches or named versions like
%'main' or 'unspecified'.

parts = strsplit(v, '.');
tf = true;
for k = 1:length(parts)
    if isnan(str2double(parts{k}))
        tf = false;
        return
    end
end

end
