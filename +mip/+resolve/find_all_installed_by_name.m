function matches = find_all_installed_by_name(packageName)
%FIND_ALL_INSTALLED_BY_NAME   Find all installed packages with a given bare name.
%
% Matches use the equivalence rules of mip.name.match (case-insensitive,
% dash/underscore-equivalent). Returned FQNs use the actual on-disk
% directory name for each match.
%
% Returns:
%   matches - Cell array of FQN strings for all org/channel combinations
%             where this name is installed.

matches = {};
packagesDir = mip.paths.get_packages_dir();
if ~exist(packagesDir, 'dir')
    return
end

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

matches = sort(matches);
end
