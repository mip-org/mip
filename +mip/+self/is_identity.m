function tf = is_identity(parsed)
%IS_IDENTITY   True when a parsed package argument names gh/mip-org/core/mip.
%
% Usage:
%   tf = mip.self.is_identity(mip.parse.parse_package_arg(arg))
%
% Checks a parsed argument struct (see mip.parse.parse_package_arg)
% against the self identity: a gh FQN with owner 'mip-org', channel
% 'core' (both strict, as owner/channel always compare), and a name
% equivalent to 'mip' (case / '-' / '_' insensitive, see mip.name.match).
% Bare names are never the identity here — callers decide separately how
% an unresolved bare 'mip' should be treated in their context.

tf = parsed.is_fqn ...
    && strcmp(parsed.type, 'gh') ...
    && strcmp(parsed.owner, 'mip-org') ...
    && strcmp(parsed.channel, 'core') ...
    && mip.name.match(parsed.name, 'mip');

end
