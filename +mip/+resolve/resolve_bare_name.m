function fqn = resolve_bare_name(packageName)
%RESOLVE_BARE_NAME   Resolve a bare package name to its fully qualified name.
%
% Searches installed packages for a name match under the equivalence
% rules of mip.name.match (case-insensitive, dash/underscore-equivalent).
% Resolution priority:
%   1. gh/mip-org/core (the default channel)
%   2. First alphabetically by FQN
%
% The returned FQN uses the actual on-disk directory name, which may
% differ in case or separators from the input.
%
% Args:
%   packageName - Bare package name (e.g. 'chebfun')
%
% Returns:
%   fqn - Canonical FQN, or empty string if not found

fqn = '';

packagesDir = mip.paths.get_packages_dir();
if ~exist(packagesDir, 'dir')
    return
end

matches = {};

topEntries = dir(packagesDir);
for i = 1:length(topEntries)
    if ~topEntries(i).isdir || startsWith(topEntries(i).name, '.')
        continue
    end
    topName = topEntries(i).name;
    topPath = fullfile(packagesDir, topName);

    if strcmp(topName, 'gh')
        ownerDirs = dir(topPath);
        for j = 1:length(ownerDirs)
            if ~ownerDirs(j).isdir || startsWith(ownerDirs(j).name, '.')
                continue
            end
            owner = ownerDirs(j).name;
            ownerPath = fullfile(topPath, owner);

            chanDirs = dir(ownerPath);
            for k = 1:length(chanDirs)
                if ~chanDirs(k).isdir || startsWith(chanDirs(k).name, '.')
                    continue
                end
                ch = chanDirs(k).name;
                candidateFqn = mip.parse.make_fqn(owner, ch, packageName);
                onDisk = mip.resolve.installed_dir(candidateFqn);
                if ~isempty(onDisk)
                    matches{end+1} = mip.parse.make_fqn(owner, ch, onDisk); %#ok<AGROW>
                end
            end
        end
    else
        candidateFqn = [topName '/' packageName];
        onDisk = mip.resolve.installed_dir(candidateFqn);
        if ~isempty(onDisk)
            matches{end+1} = [topName '/' onDisk]; %#ok<AGROW>
        end
    end
end

if isempty(matches)
    return
end

% Priority: gh/mip-org/core first
for i = 1:length(matches)
    if startsWith(matches{i}, 'gh/mip-org/core/')
        fqn = matches{i};
        return
    end
end

matches = sort(matches);
fqn = matches{1};

end
