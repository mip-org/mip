function fqn = canonical_installed_fqn(fqnStr)
%CANONICAL_INSTALLED_FQN   Canonicalize an FQN to its installed on-disk form.
%
% If a package equivalent to fqnStr is installed (name matched case- and
% -/_-insensitively), returns the FQN with the on-disk name, so it matches
% the form recorded in the state stores (loaded lists,
% directly_installed.txt). Otherwise returns the canonical typed FQN
% unchanged; callers then report not-installed / not-loaded in their own
% terms.
%
% Args:
%   fqnStr - Fully qualified name string (any accepted FQN input form).
%
% Returns:
%   fqn - Canonical FQN string.

    r = mip.parse.parse_package_arg(fqnStr);
    onDisk = mip.resolve.installed_dir(r.fqn);
    if isempty(onDisk)
        fqn = r.fqn;
    elseif strcmp(r.type, 'gh')
        fqn = mip.parse.make_fqn(r.owner, r.channel, onDisk);
    else
        fqn = [r.type '/' onDisk];
    end
end
