function prune_unused_packages()
%PRUNE_UNUSED_PACKAGES   Remove installed packages that are no longer needed.
%
% A package is considered needed if it is in `directly_installed.txt` or
% is a transitive dependency of any directly-installed package.
%
% `gh/mip-org/core/mip` (the package manager itself) is never pruned.
%
% Used by:
%   - `mip uninstall`: prune orphans after removing requested packages.
%   - `mip install`: roll back successfully-installed dependencies when a
%     later package in the same operation fails.

    allInstalled = mip.state.list_installed_packages();

    if isempty(allInstalled)
        return
    end

    directlyInstalled = mip.state.get_directly_installed();

    % Build set of all needed packages (directly installed + their dependencies)
    neededPackages = {};
    for i = 1:length(directlyInstalled)
        directPkg = directlyInstalled{i};
        if ismember(directPkg, allInstalled)
            neededPackages = [neededPackages, mip.dependency.find_all_dependencies(directPkg)]; %#ok<AGROW>
        end
    end

    neededPackages = unique([directlyInstalled, neededPackages]);

    % Find packages to prune (installed but not needed)
    % Never prune gh/mip-org/core/mip - it is the package manager itself
    packagesToPrune = {};
    for i = 1:length(allInstalled)
        fqn = allInstalled{i};
        if ~ismember(fqn, neededPackages) && ...
                ~strcmp(fqn, 'gh/mip-org/core/mip')
            packagesToPrune{end+1} = fqn; %#ok<AGROW>
        end
    end

    if ~isempty(packagesToPrune)
        displayFqns = cellfun(@mip.parse.display_fqn, packagesToPrune, 'UniformOutput', false);
        fprintf('\nPruning unnecessary packages: %s\n', strjoin(displayFqns, ', '));
        packagesDir = mip.paths.get_packages_dir();
        for i = 1:length(packagesToPrune)
            fqn = packagesToPrune{i};
            r = mip.parse.parse_package_arg(fqn);
            pkgDir = mip.paths.get_package_dir(fqn);

            try
                rmdir(pkgDir, 's');
                fprintf('  Pruned package "%s"\n', mip.parse.display_fqn(fqn));
                if strcmp(r.type, 'gh')
                    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh', r.owner, r.channel));
                    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh', r.owner));
                    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh'));
                else
                    mip.paths.cleanup_empty_dirs(fullfile(packagesDir, r.type));
                end
            catch ME
                warning('mip:pruneFailed', ...
                        'Failed to prune package "%s": %s', mip.parse.display_fqn(fqn), ME.message);
            end
        end
    end
end
