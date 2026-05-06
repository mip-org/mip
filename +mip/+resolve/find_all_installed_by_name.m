function matches = find_all_installed_by_name(packageName)
%FIND_ALL_INSTALLED_BY_NAME   Find all installed packages with a given bare name.
%
% Matches use the equivalence rules of mip.name.match (case-insensitive,
% dash/underscore-equivalent). Returned FQNs use the actual on-disk
% directory name for each match and include the 'gh/' prefix for
% GitHub channel packages.
%
% Returns:
%   matches - Cell array of canonical FQN strings for each source-type /
%             owner / channel combination where this name is installed.

matches = {};
packagesDir = mip.paths.get_packages_dir();
if ~exist(packagesDir, 'dir')
    return
end

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

matches = sort(matches);
end
