function out = installed_fqn(fqn)
%INSTALLED_FQN   Canonicalize an FQN to its on-disk installed form.
%
% Looks up the actual on-disk directory name for the FQN's last component
% (case- and dash/underscore-insensitive, see mip.resolve.installed_dir)
% and returns the FQN rebuilt with that name. Commands canonicalize user
% input through this once at their boundary, so that stored FQNs and
% state lookups can use plain string comparison.
%
% A 2-part '<owner>/<name>' argument resolves to the repository package
% gh/<owner>/<name> if it is installed, and otherwise to the personal-
% channel package gh/<owner>/<owner>/<name> (see the .fallback_fqn field
% of mip.parse.parse_package_arg).
%
% Args:
%   fqn - FQN in any accepted input form (see mip.parse.parse_package_arg),
%         optionally with an @version suffix, which is ignored.
%
% Returns:
%   out - Canonical FQN with the on-disk name, or '' if not installed.

r = mip.parse.parse_package_arg(fqn);
out = rebuild(r);
if isempty(out) && ~isempty(r.fallback_fqn)
    out = rebuild(mip.parse.parse_package_arg(r.fallback_fqn));
end

end

function out = rebuild(r)
onDisk = mip.resolve.installed_dir(r.fqn);
if isempty(onDisk)
    out = '';
elseif strcmp(r.type, 'gh')
    out = mip.parse.make_fqn(r.owner, r.channel, onDisk);
else
    out = [r.type '/' onDisk];
end
end
