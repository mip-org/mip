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

    % Find installed packages no longer needed by any directly-installed package
    packagesToPrune = mip.dependency.find_orphans(directlyInstalled, allInstalled);

    if ~isempty(packagesToPrune)
        displayFqns = cellfun(@mip.parse.display_fqn, packagesToPrune, 'UniformOutput', false);
        fprintf('\nPruning unnecessary packages: %s\n', strjoin(displayFqns, ', '));
        for i = 1:length(packagesToPrune)
            fqn = packagesToPrune{i};
            pkgDir = mip.paths.get_package_dir(fqn);

            try
                mip.paths.remove_dir(pkgDir);
                fprintf('  Pruned package "%s"\n', mip.parse.display_fqn(fqn));
                mip.paths.cleanup_package_parents(fqn);
            catch ME
                warning('mip:pruneFailed', ...
                        'Failed to prune package "%s": %s', mip.parse.display_fqn(fqn), ME.message);
            end
        end
    end
end
