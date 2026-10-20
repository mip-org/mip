function out = canonical_fqn(package)
%CANONICAL_FQN   Canonicalize a package FQN to its canonical internal form.
%
% Accepts either a canonical FQN or a user-facing shorthand (which omits
% the 'gh/' prefix). Returns the canonical FQN. Non-FQN inputs (bare
% names) are returned unchanged. A 2-part '<owner>/<name>' input maps to
% the repository FQN gh/<owner>/<name>, unless only the personal-channel
% package gh/<owner>/<owner>/<name> is installed, in which case it maps
% to that.
%
% This is used at API boundaries where callers may pass either form —
% primarily the state lookup functions (is_loaded, is_installed, etc).
%
% Args:
%   package - FQN string (canonical or 3-part shorthand) or bare name
%
% Returns:
%   out - Canonical FQN string (or the original input if it isn't an FQN)

try
    r = mip.parse.parse_package_arg(package);
catch
    out = package;
    return
end

if ~r.is_fqn
    out = package;
    return
end

out = r.fqn;
if ~isempty(r.fallback_fqn) && isempty(mip.resolve.installed_dir(r.fqn)) ...
        && ~isempty(mip.resolve.installed_dir(r.fallback_fqn))
    out = r.fallback_fqn;
end

end
