function out = display_fqn(fqn)
%DISPLAY_FQN   Convert an internal FQN to its user-facing display form.
%
% GitHub packages are stored internally with a leading 'gh/' source-type
% prefix (e.g. 'gh/mip-org/core/chebfun' for a channel package,
% 'gh/fastalgorithms/chunkie' for a repository package). The 'gh/' prefix
% is stripped for display, so a repository package displays as the same
% '<owner>/<repo>' string the user types to install it. Personal-channel
% packages are not collapsed: 'gh/magland/magland/chunkie' displays as
% 'magland/magland/chunkie', since 'magland/chunkie' now refers to the
% repository github.com/magland/chunkie.
%
% The prefix is kept for a repository package whose owner matches a
% reserved source-type prefix (mip.parse.reserved_types), since the
% stripped form would be parsed back as a non-gh FQN rather than
% round-tripping to the original. Other source types ('local/mypkg',
% 'fex/some_pkg', etc.) are returned unchanged.
%
% Args:
%   fqn - Internal fully qualified name
%
% Returns:
%   out - User-facing display form
%
% Examples:
%   display_fqn('gh/mip-org/core/chebfun')    -> 'mip-org/core/chebfun'
%   display_fqn('gh/fastalgorithms/chunkie')  -> 'fastalgorithms/chunkie'
%   display_fqn('gh/magland/magland/chunkie') -> 'magland/magland/chunkie'
%   display_fqn('gh/local/foo')               -> 'gh/local/foo'
%   display_fqn('local/mypkg')                -> 'local/mypkg'

if startsWith(fqn, 'gh/')
    rest = fqn(4:end);
    parts = strsplit(rest, '/');
    if numel(parts) == 2 && ismember(parts{1}, mip.parse.reserved_types())
        out = fqn;
    else
        out = rest;
    end
else
    out = fqn;
end

end
