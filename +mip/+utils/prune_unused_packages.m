function prune_unused_packages()
%PRUNE_UNUSED_PACKAGES   Remove installed packages that are no longer needed.
%
% A package is considered needed if it is in `directly_installed.txt` or
% is a transitive dependency of any directly-installed package.
%
% `mip-org/core/mip` (the package manager itself) is never pruned.
%
% Used by:
%   - `mip uninstall`: prune orphans after removing requested packages.
%   - `mip install`: roll back successfully-installed dependencies when a
%     later package in the same operation fails.

    allInstalled = mip.utils.list_installed_packages();

    if isempty(allInstalled)
        return
    end

    directlyInstalled = mip.utils.get_directly_installed();

    % Build set of all needed packages (directly installed + their dependencies)
    neededPackages = {};
    for i = 1:length(directlyInstalled)
        directPkg = directlyInstalled{i};
        if ismember(directPkg, allInstalled)
            neededPackages = [neededPackages, mip.utils.get_all_dependencies(directPkg)]; %#ok<AGROW>
        end
    end

    neededPackages = unique([directlyInstalled, neededPackages]);

    % Find packages to prune (installed but not needed)
    % Never prune mip-org/core/mip - it is the package manager itself
    packagesToPrune = {};
    for i = 1:length(allInstalled)
        fqn = allInstalled{i};
        if ~ismember(fqn, neededPackages) && ...
                ~strcmp(fqn, 'mip-org/core/mip')
            packagesToPrune{end+1} = fqn; %#ok<AGROW>
        end
    end

    if ~isempty(packagesToPrune)
        fprintf('\nPruning unnecessary packages: %s\n', strjoin(packagesToPrune, ', '));
        for i = 1:length(packagesToPrune)
            fqn = packagesToPrune{i};
            r = mip.utils.parse_package_arg(fqn);
            pkgDir = mip.utils.get_package_dir(r.org, r.channel, r.name);

            try
                rmdir(pkgDir, 's');
                fprintf('  Pruned package "%s"\n', fqn);
                mip.utils.cleanup_empty_dirs(fullfile(mip.utils.get_packages_dir(), r.org, r.channel));
                mip.utils.cleanup_empty_dirs(fullfile(mip.utils.get_packages_dir(), r.org));
            catch ME
                warning('mip:pruneFailed', ...
                        'Failed to prune package "%s": %s', fqn, ME.message);
            end
        end
    end
end
