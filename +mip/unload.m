function unload(varargin)
%UNLOAD   Unload one or more mip packages from MATLAB path.
%
% Usage:
%   mip unload <package>
%   mip unload <package1> <package2> ...
%   mip unload <owner>/<channel>/<package>
%   mip unload --all
%   mip unload --all --force
%
% Accepts both bare package names and fully qualified names.
% Use --all to unload all non-sticky packages.
% Use --all --force to unload all packages including sticky ones.
%
% Bulk unloads never unload the running mip: gh/mip-org/core/mip, plus
% the loaded package actually providing the running mip code when that
% is a different one (e.g. a preview build loaded over the released mip;
% see mip.self.running_mip_fqn). Explicitly naming a preview build still
% unloads it — that is how a preview is exited.

    % Check for --all and --force flags
    [opts, packageArgs] = mip.parse.flags(varargin, struct('all', false, 'force', false));

    % Handle --all flag
    if opts.all
        unloadAll(opts.force);
        return
    end

    if isempty(packageArgs)
        error('mip:noPackage', 'No package name specified for unload command.');
    end

    % Unload each package
    for k = 1:length(packageArgs)
        packageArg = packageArgs{k};

        % Resolve to FQN
        fqn = resolveLoadedFqn(packageArg);

        % gh/mip-org/core/mip cannot be unloaded
        if strcmp(fqn, 'gh/mip-org/core/mip')
            error('mip:cannotUnloadMip', 'Cannot unload mip itself.');
        end

        displayFqn = mip.parse.display_fqn(fqn);

        % Check if package is loaded
        if ~mip.state.is_loaded(fqn)
            fprintf('Package "%s" is not currently loaded\n', displayFqn);
            continue
        end

        % Get package directory
        r = mip.parse.parse_package_arg(fqn);
        if r.is_fqn
            packageDir = mip.paths.get_package_dir(fqn);
        else
            packageDir = '';
        end

        % Remove paths declared in mip.json
        executeUnload(packageDir, fqn);

        % Remove from all load-state lists
        mip.state.set_unloaded(fqn);

        fprintf('Unloaded package "%s"\n', displayFqn);
    end

    % Prune packages that are no longer needed (once, after all unloads)
    pruneUnusedPackages();
end

function fqn = resolveLoadedFqn(packageArg)
% Resolve a package argument to its FQN among loaded packages.

    result = mip.parse.parse_package_arg(packageArg);

    if result.is_fqn
        % Canonicalize to the on-disk name so we match the form stored in
        % MIP_LOADED_PACKAGES. If not installed at all, fall back to the
        % canonical typed form (caller will report "not loaded").
        fqn = mip.resolve.installed_fqn(result.fqn);
        if isempty(fqn)
            fqn = result.fqn;
        end
        return
    end

    % Search loaded packages for a bare name match; the most recently
    % loaded match wins.
    fqn = mip.resolve.resolve_to_loaded(result.name);
    if isempty(fqn)
        fqn = result.name;  % Return bare name; caller will handle "not loaded"
    end
end

function executeUnload(packageDir, fqn)
    displayFqn = mip.parse.display_fqn(fqn);

    % Remove paths declared in mip.json. Missing packageDir or unreadable
    % mip.json are non-fatal -- the sweep below is the backstop.
    pkgInfo = [];
    if ~isempty(packageDir) && isfolder(packageDir)
        try
            pkgInfo = mip.config.read_package_json(packageDir);
        catch
            pkgInfo = [];
        end
    end
    hasPathsField = ~isempty(pkgInfo) && isfield(pkgInfo, 'paths');
    if hasPathsField
        srcDir = mip.paths.get_source_dir(packageDir, pkgInfo);
        oldState = warning('off', 'MATLAB:rmpath:DirNotFound');
        restoreWarn = onCleanup(@() warning(oldState));
        for i = 1:length(pkgInfo.paths)
            rel = pkgInfo.paths{i};
            if strcmp(rel, '.')
                target = srcDir;
            else
                target = fullfile(srcDir, rel);
            end
            rmpath(target);
        end
        clear restoreWarn;
    else
        warning('mip:unloadNotFound', ...
                'Package "%s" has no "paths" field in mip.json. Path changes may persist.', ...
                displayFqn);
    end

    % Defensive sweep: remove any remaining MATLAB path entries that fall
    % under this package's source directory. This catches paths added via
    % `mip load --addpath` that the mip.json "paths" list did not cover.
    sweepPathEntries(packageDir, fqn, pkgInfo);

    % Unload any compiled MEX this package shipped, so a later uninstall or
    % update can delete the package directory -- a loaded DLL/MEX cannot be
    % removed on Windows while it is held by the process.
    clearPackageMex(packageDir, pkgInfo);
end

function clearPackageMex(packageDir, pkgInfo)
% Clear the MEX binaries under a package's source directory.
    if isempty(packageDir)
        return
    end
    if ~isempty(pkgInfo)
        srcDir = mip.paths.get_source_dir(packageDir, pkgInfo);
    else
        % mip.json unreadable: fall back to scanning the package dir, which
        % for a non-editable install contains the source subdir.
        srcDir = packageDir;
    end
    mip.build.clear_mex(srcDir);
end

function sweepPathEntries(packageDir, fqn, pkgInfo)
% Remove any MATLAB path entries that lie under the package source dir.
% Silent if the package was already cleanly unloaded above.

    if isempty(packageDir)
        return
    end
    if nargin < 3 || isempty(pkgInfo)
        if ~isfolder(packageDir)
            return
        end
        try
            pkgInfo = mip.config.read_package_json(packageDir);
        catch
            return
        end
    end
    srcDir = mip.paths.get_source_dir(packageDir, pkgInfo);
    if ~isfolder(srcDir)
        return
    end

    % Normalize the prefix so startsWith comparisons are accurate. We
    % match `srcDir` exactly OR `srcDir<filesep>...`, never a sibling
    % directory whose name happens to share a prefix.
    prefixWithSep = [srcDir, filesep];
    entries = strsplit(path, pathsep);
    toRemove = {};
    for k = 1:numel(entries)
        e = entries{k};
        if isempty(e)
            continue
        end
        if strcmp(e, srcDir) || startsWith(e, prefixWithSep)
            toRemove{end+1} = e; %#ok<AGROW>
        end
    end

    if isempty(toRemove)
        return
    end
    oldState = warning('off', 'MATLAB:rmpath:DirNotFound');
    restoreWarn = onCleanup(@() warning(oldState));
    displayFqn = mip.parse.display_fqn(fqn);
    for k = 1:numel(toRemove)
        rmpath(toRemove{k});
        fprintf('  swept residual path entry for "%s": %s\n', displayFqn, toRemove{k});
    end
end

function pruneUnusedPackages()
% Prune packages that are no longer needed.

    MIP_LOADED_PACKAGES          = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    MIP_DIRECTLY_LOADED_PACKAGES = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');

    if isempty(MIP_LOADED_PACKAGES)
        return
    end

    % Find loaded packages no longer needed by any directly-loaded package.
    % The package providing the running mip is never pruned (like the core
    % identity, which find_orphans already exempts).
    packagesToPrune = mip.dependency.find_orphans(MIP_DIRECTLY_LOADED_PACKAGES, MIP_LOADED_PACKAGES);
    runningMip = mip.self.running_mip_fqn();
    if ~isempty(runningMip)
        packagesToPrune = packagesToPrune(~strcmp(packagesToPrune, runningMip));
    end

    % Prune each unnecessary package
    if ~isempty(packagesToPrune)
        displayPrune = cellfun(@mip.parse.display_fqn, packagesToPrune, 'UniformOutput', false);
        fprintf('Unloading transitive dependencies: %s\n', strjoin(displayPrune, ', '));
        for i = 1:length(packagesToPrune)
            pkg = packagesToPrune{i};
            packageDir = mip.paths.get_package_dir(pkg);
            executeUnload(packageDir, pkg);
            mip.state.key_value_remove('MIP_LOADED_PACKAGES', pkg);
            fprintf('  Unloaded transitive dependency "%s"\n', mip.parse.display_fqn(pkg));
        end
    end

    % After pruning, check for broken dependencies
    mip.state.check_broken_dependencies('loaded');
end

function unloadAll(forceUnload)
    MIP_LOADED_PACKAGES          = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    MIP_DIRECTLY_LOADED_PACKAGES = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
    MIP_STICKY_PACKAGES          = mip.state.key_value_get('MIP_STICKY_PACKAGES');

    if isempty(MIP_LOADED_PACKAGES)
        fprintf('No packages are currently loaded\n');
        return
    end

    % Find packages to unload. The running mip is never unloaded here:
    % gh/mip-org/core/mip, plus the loaded package actually providing the
    % running mip code when that is a different one (a preview build
    % loaded over the released mip). Explicit `mip unload <pkg>` of a
    % preview build still works — only the bulk forms spare it.
    runningMip = mip.self.running_mip_fqn();
    packagesToUnload = {};
    if forceUnload
        for i = 1:length(MIP_LOADED_PACKAGES)
            pkg = MIP_LOADED_PACKAGES{i};
            if ~isRunningMip(pkg, runningMip)
                packagesToUnload{end+1} = pkg; %#ok<AGROW>
            end
        end
    else
        for i = 1:length(MIP_LOADED_PACKAGES)
            pkg = MIP_LOADED_PACKAGES{i};
            if ~ismember(pkg, MIP_STICKY_PACKAGES) && ~isRunningMip(pkg, runningMip)
                packagesToUnload{end+1} = pkg; %#ok<AGROW>
            end
        end
    end

    if isempty(packagesToUnload)
        fprintf('No packages to unload\n');
        if ~forceUnload && ~isempty(MIP_STICKY_PACKAGES)
            stickyDisplay = cellfun(@mip.parse.display_fqn, MIP_STICKY_PACKAGES, 'UniformOutput', false);
            fprintf('Sticky packages remain: %s\n', strjoin(stickyDisplay, ', '));
        end
        return
    end

    unloadDisplay = cellfun(@mip.parse.display_fqn, packagesToUnload, 'UniformOutput', false);
    if forceUnload
        fprintf('Unloading all packages: %s\n', strjoin(unloadDisplay, ', '));
    else
        if ~isempty(MIP_STICKY_PACKAGES)
            fprintf('Unloading all non-sticky packages: %s\n', strjoin(unloadDisplay, ', '));
        else
            fprintf('Unloading all packages: %s\n', strjoin(unloadDisplay, ', '));
        end
    end

    % Unload each package
    for i = 1:length(packagesToUnload)
        pkg = packagesToUnload{i};
        packageDir = mip.paths.get_package_dir(pkg);
        executeUnload(packageDir, pkg);
        fprintf('  Unloaded package "%s"\n', mip.parse.display_fqn(pkg));
    end

    % Update global variables: the survivors keep their load order and
    % their direct/sticky flags (mip itself always remains loaded and
    % sticky).
    survivors = MIP_LOADED_PACKAGES(~ismember(MIP_LOADED_PACKAGES, packagesToUnload));
    MIP_LOADED_PACKAGES = survivors;
    MIP_DIRECTLY_LOADED_PACKAGES = MIP_DIRECTLY_LOADED_PACKAGES( ...
        ismember(MIP_DIRECTLY_LOADED_PACKAGES, survivors));
    if forceUnload
        MIP_STICKY_PACKAGES = MIP_STICKY_PACKAGES(ismember(MIP_STICKY_PACKAGES, survivors));
        if ~ismember('gh/mip-org/core/mip', MIP_LOADED_PACKAGES)
            MIP_LOADED_PACKAGES{end+1} = 'gh/mip-org/core/mip';
        end
        if ~ismember('gh/mip-org/core/mip', MIP_STICKY_PACKAGES)
            MIP_STICKY_PACKAGES{end+1} = 'gh/mip-org/core/mip';
        end
    end

    mip.state.key_value_set('MIP_LOADED_PACKAGES', MIP_LOADED_PACKAGES);
    mip.state.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', MIP_DIRECTLY_LOADED_PACKAGES);
    mip.state.key_value_set('MIP_STICKY_PACKAGES', MIP_STICKY_PACKAGES);

    mip.state.check_broken_dependencies('loaded');
end

function tf = isRunningMip(pkg, runningMip)
    tf = strcmp(pkg, 'gh/mip-org/core/mip') || ...
         (~isempty(runningMip) && strcmp(pkg, runningMip));
end
