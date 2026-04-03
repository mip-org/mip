function matches = find_all_installed_by_name(packageName)
%FIND_ALL_INSTALLED_BY_NAME   Find all installed packages with a given bare name.
%
% Returns cell array of FQN strings for all org/channel combinations
% where this package name is installed.

matches = {};
packagesDir = mip.utils.get_packages_dir();
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
        pkgDir = fullfile(orgPath, ch, packageName);
        if exist(pkgDir, 'dir')
            matches{end+1} = mip.utils.make_fqn(org, ch, packageName); %#ok<AGROW>
        end
    end
end

matches = sort(matches);
end
