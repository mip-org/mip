function out = installed_fqn(fqn)
%INSTALLED_FQN   Canonicalize an FQN to its on-disk installed form.
%
% Looks up the actual on-disk directory name for the FQN's last component
% (case- and dash/underscore-insensitive, see mip.resolve.installed_dir)
% and returns the FQN rebuilt with that name. Commands canonicalize user
% input through this once at their boundary, so that stored FQNs and
% state lookups can use plain string comparison.
%
% Args:
%   fqn - FQN in any accepted input form (see mip.parse.parse_package_arg)
%
% Returns:
%   out - Canonical FQN with the on-disk name, or '' if not installed.

r = mip.parse.parse_package_arg(fqn);
onDisk = mip.resolve.installed_dir(r.fqn);
if isempty(onDisk)
    out = '';
elseif strcmp(r.type, 'gh')
    out = mip.parse.make_fqn(r.owner, r.channel, onDisk);
else
    out = [r.type '/' onDisk];
end

end
