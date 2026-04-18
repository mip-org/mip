function fqn = resolve_bare_name(packageName)
%RESOLVE_BARE_NAME   Resolve a bare package name to its fully qualified name.
%
% Searches installed packages for a name match under the equivalence
% rules of mip.name.match (case-insensitive, dash/underscore-equivalent).
% Resolution priority:
%   1. mip-org/core (the default channel)
%   2. First alphabetically by org/channel
%
% The returned FQN uses the actual on-disk directory name, which may
% differ in case or separators from the input.
%
% Args:
%   packageName - Bare package name (e.g. 'chebfun')
%
% Returns:
%   fqn - Fully qualified name, or empty string if not found

fqn = '';

packagesDir = mip.paths.get_packages_dir();
if ~exist(packagesDir, 'dir')
    return
end

% Collect all matches: per channel, do a case-insensitive lookup.
matches = {};

orgDirs = dir(packagesDir);
for i = 1:length(orgDirs)
    if ~orgDirs(i).isdir || startsWith(orgDirs(i).name, '.')
        continue
    end
    org = orgDirs(i).name;
    orgPath = fullfile(packagesDir, org);

    chanDirs = dir(orgPath);
    for j = 1:length(chanDirs)
        if ~chanDirs(j).isdir || startsWith(chanDirs(j).name, '.')
            continue
        end
        ch = chanDirs(j).name;
        onDisk = mip.resolve.installed_dir(org, ch, packageName);
        if ~isempty(onDisk)
            matches{end+1} = mip.parse.make_fqn(org, ch, onDisk); %#ok<AGROW>
        end
    end
end

if isempty(matches)
    return
end

% Priority: mip-org/core first
for i = 1:length(matches)
    if startsWith(matches{i}, 'mip-org/core/')
        fqn = matches{i};
        return
    end
end

% Otherwise, first alphabetically
matches = sort(matches);
fqn = matches{1};

end
