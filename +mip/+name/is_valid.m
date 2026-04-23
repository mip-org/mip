function tf = is_valid(name)
%IS_VALID   Check if a string is a valid user-input package name.
%
% User-input names may mix upper- and lower-case, and hyphens and
% underscores are both allowed (they're treated as equivalent at lookup
% time via mip.name.normalize). A valid name must consist of letters,
% digits, hyphens, and underscores, and must start and end with a letter
% or digit.
%
% Use this when validating names the user types on the command line
% (install, load, update, uninstall, etc.). For the canonical form that
% gets stored in mip.yaml or used as an on-disk directory / FQN, use
% mip.name.is_valid_canonical instead.
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
tf = ~isempty(regexp(name, '^[a-zA-Z0-9]([-a-zA-Z0-9_]*[a-zA-Z0-9])?$', 'once'));

end
