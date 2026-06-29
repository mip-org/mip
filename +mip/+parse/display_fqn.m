function out = display_fqn(fqn)
%DISPLAY_FQN   Convert an internal FQN to its user-facing display form.
%
% GitHub channel packages are stored internally with a leading 'gh/'
% source-type prefix (e.g. 'gh/mip-org/core/chebfun'). The 'gh/' prefix
% is always stripped for display. For personal channels — where the
% channel name equals the owner (e.g. 'gh/magland/magland/chunkie') —
% the duplicated owner segment is collapsed, yielding the 2-part form
% '<owner>/<pkg>'. The collapse is skipped when the owner matches a
% reserved source-type prefix (mip.parse.reserved_types), since the
% collapsed form would be parsed back as a non-gh FQN rather than
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
%   display_fqn('gh/magland/magland/chunkie') -> 'magland/chunkie'
%   display_fqn('local/mypkg')                -> 'local/mypkg'

if startsWith(fqn, 'gh/')
    rest = fqn(4:end);
    parts = strsplit(rest, '/');
    if numel(parts) == 3 && strcmp(parts{1}, parts{2}) && ...
            ~ismember(parts{1}, mip.parse.reserved_types())
        out = [parts{1} '/' parts{3}];
    else
        out = rest;
    end
else
    out = fqn;
end

end
