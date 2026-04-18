function name = installed_dir(org, channel, requestedName)
%INSTALLED_DIR   Find the on-disk directory name for an installed package.
%
% Scans `<root>/packages/<org>/<channel>/` for a directory whose name
% matches requestedName under the equivalence rules of mip.name.match
% (case-insensitive, dash/underscore-equivalent).
%
% The returned name is the actual directory name on disk, preserving its
% case and separators. Callers use this form as the canonical package
% name for subsequent storage and comparison, so that plain strcmp/
% ismember against already-stored FQNs keeps working.
%
% Args:
%   org           - Organization name (case-sensitive)
%   channel       - Channel name (case-sensitive)
%   requestedName - Package name (char or string)
%
% Returns:
%   name - char row vector with the on-disk name, or '' if no matching
%          directory exists.

name = '';

chanPath = fullfile(mip.paths.get_packages_dir(), char(org), char(channel));
if ~exist(chanPath, 'dir')
    return
end

entries = dir(chanPath);
for i = 1:length(entries)
    if ~entries(i).isdir || startsWith(entries(i).name, '.')
        continue
    end
    if mip.name.match(entries(i).name, requestedName)
        name = entries(i).name;
        return
    end
end

end
