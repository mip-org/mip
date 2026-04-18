function n = normalize(s)
%NORMALIZE   Canonical form of a package name for equivalence comparison.
%
% Lowercases the input and replaces hyphens with underscores. Two package
% names are considered equivalent (see mip.name.match) iff their
% normalized forms are equal. Org and channel components are NOT subject
% to this normalization — they map to GitHub paths and remain
% case-sensitive.
%
% Args:
%   s - char or string scalar
%
% Returns:
%   n - char row vector, normalized

if isstring(s)
    s = char(s);
end
if ~ischar(s)
    error('mip:name:invalidInput', ...
          'mip.name.normalize expects char or string, got %s.', class(s));
end

n = strrep(lower(s), '-', '_');

end
