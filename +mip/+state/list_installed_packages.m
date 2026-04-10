function packages = list_installed_packages()
%LIST_INSTALLED_PACKAGES   List all installed packages as fully qualified names.
%
% Returns:
%   packages - Cell array of FQN strings like {'mip-org/core/chebfun', ...}

packages = {};

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
        chanPath = fullfile(orgPath, ch);

        pkgDirs = dir(chanPath);
        for k = 1:length(pkgDirs)
            if ~pkgDirs(k).isdir || startsWith(pkgDirs(k).name, '.')
                continue
            end
            packages{end+1} = mip.parse.make_fqn(org, ch, pkgDirs(k).name); %#ok<AGROW>
        end
    end
end

packages = sort(packages);

end
