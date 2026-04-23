function tf = is_valid_canonical(name)
%IS_VALID_CANONICAL   Check if a string is a valid canonical package name.
%
% The canonical form of a package name is lowercase letters, digits,
% hyphens, and underscores, starting and ending with a letter or digit.
% Hyphens and underscores are DISTINCT characters in the canonical form
% (they become interchangeable only at user-input lookup time, see
% mip.name.normalize).
%
% Use this when creating or storing a package name: mip.init writes this
% into mip.yaml, `mip install <name> --url <zip>` uses it as the install
% directory, and the channel's prepare step enforces it on published
% packages. For validating names the user types on the command line, use
% mip.name.is_valid.
%
% Args:
%   name - char or string scalar
%
% Returns:
%   tf - logical scalar

if isstring(name)
    name = char(name);
end
if ~ischar(name) || isempty(name)
    tf = false;
    return;
end
tf = ~isempty(regexp(name, '^[a-z0-9]([-a-z0-9_]*[a-z0-9])?$', 'once'));

end
