function tf = is_numeric_version(v)
%IS_NUMERIC_VERSION   True when v is a dot-separated sequence of numeric
%components (e.g. '1', '0.5.0'). Used by version-selection code to
%distinguish numeric releases from branches or named versions like
%'main' or 'master'.
%
% Each component must consist solely of digits; signs, exponents, and
% named floats ('inf', 'nan') do not count. This matches the channel
% build's definition (mip_channel_tools) so both sides agree on which
% release-directory names are numeric.

parts = strsplit(v, '.');
tf = true;
for k = 1:length(parts)
    if isempty(regexp(parts{k}, '^\d+$', 'once'))
        tf = false;
        return
    end
end

end
