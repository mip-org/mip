function unload(varargin)
%UNLOAD   Unload one or more mip packages from MATLAB path.
%
% Usage:
%   mip.unload('packageName')
%   mip.unload('package1', 'package2', ...)
%   mip.unload('org/channel/packageName')
%   mip.unload('--all')
%   mip.unload('--all', '--force')
%
% Accepts both bare package names and fully qualified names.
% Use '--all' to unload all non-sticky packages.
% Use '--all --force' to unload all packages including sticky ones.

    % Check for --all and --force flags
    hasAll = any(strcmp(varargin, '--all'));
    hasForce = any(strcmp(varargin, '--force'));

    % Handle --all flag
    if hasAll
        unloadAll(hasForce);
        return
    end

    % Collect all non-flag arguments as package names
    packageArgs = {};
    for i = 1:length(varargin)
        if ~startsWith(varargin{i}, '--')
            packageArgs{end+1} = varargin{i};
        end
    end

    if isempty(packageArgs)
        error('mip:noPackage', 'No package name specified for unload command.');
    end

    % Unload each package
    for k = 1:length(packageArgs)
        packageArg = packageArgs{k};

        % Resolve to FQN
        fqn = resolveLoadedFqn(packageArg);

        % mip-org/core/mip cannot be unloaded
        if strcmp(fqn, 'mip-org/core/mip')
            error('mip:cannotUnloadMip', 'Cannot unload mip itself.');
        end

        % Check if package is loaded
        if ~mip.state.is_loaded(fqn)
            fprintf('Package "%s" is not currently loaded\n', fqn);
            continue
        end

        % Get package directory
        result = mip.parse.parse_package_arg(fqn);
        packageDir = mip.paths.get_package_dir(result.org, result.channel, result.name);

        % Execute unload_package.m if it exists
        executeUnload(packageDir, fqn);

        % Remove from all load-state lists
        mip.state.set_unloaded(fqn);

        fprintf('Unloaded package "%s"\n', fqn);
    end

    % Prune packages that are no longer needed (once, after all unloads)
    pruneUnusedPackages();
end

function fqn = resolveLoadedFqn(packageArg)
% Resolve a package argument to its FQN among loaded packages.

    result = mip.parse.parse_package_arg(packageArg);

    if result.is_fqn
        fqn = packageArg;
        return
    end

    % Search loaded packages for a bare name match
    loadedPackages = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    matches = {};
    for i = 1:length(loadedPackages)
        loaded = loadedPackages{i};
        r = mip.parse.parse_package_arg(loaded);
        if r.is_fqn && strcmp(r.name, result.name)
            matches{end+1} = loaded; %#ok<AGROW>
        end
    end

    if isempty(matches)
        fqn = result.name;  % Return bare name; caller will handle "not loaded"
        return
    end

    if length(matches) == 1
        fqn = matches{1};
        return
    end

    % Multiple matches: pick the most recently loaded (last in load order)
    lastIdx = 0;
    for i = 1:length(matches)
        for j = 1:length(loadedPackages)
            if strcmp(loadedPackages{j}, matches{i}) && j > lastIdx
                lastIdx = j;
            end
        end
    end
    fqn = loadedPackages{lastIdx};
end

function executeUnload(packageDir, fqn)
    unloadFile = fullfile(packageDir, 'unload_package.m');

    if ~exist(unloadFile, 'file')
        warning('mip:unloadNotFound', ...
                'Package "%s" does not have a unload_package.m file. Path changes may persist.', ...
                fqn);
        return
    end

    originalDir = pwd;
    cd(packageDir);
    try
        run(unloadFile);
    catch ME
        warning('mip:unloadError', ...
                'Error executing unload_package.m for package "%s": %s', ...
                fqn, ME.message);
    end
    cd(originalDir);
end

function pruneUnusedPackages()
% Prune packages that are no longer needed.

    MIP_LOADED_PACKAGES          = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    MIP_DIRECTLY_LOADED_PACKAGES = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');

    if isempty(MIP_LOADED_PACKAGES)
        return
    end

    % Build set of all needed packages (directly loaded + their dependencies)
    neededPackages = {};
    for i = 1:length(MIP_DIRECTLY_LOADED_PACKAGES)
        directPkg = MIP_DIRECTLY_LOADED_PACKAGES{i};
        neededPackages = [neededPackages, mip.dependency.find_all_dependencies(directPkg)]; %#ok<*AGROW>
    end

    % Add directly loaded packages themselves
    neededPackages = unique([MIP_DIRECTLY_LOADED_PACKAGES, neededPackages]);

    % Find packages to prune (loaded but not needed)
    % Never prune mip-org/core/mip - it is the package manager itself
    packagesToPrune = {};
    for i = 1:length(MIP_LOADED_PACKAGES)
        pkg = MIP_LOADED_PACKAGES{i};
        if ~ismember(pkg, neededPackages) && ~strcmp(pkg, 'mip-org/core/mip')
            packagesToPrune{end+1} = pkg;
        end
    end

    % Prune each unnecessary package
    if ~isempty(packagesToPrune)
        fprintf('Pruning unnecessary packages: %s\n', strjoin(packagesToPrune, ', '));
        for i = 1:length(packagesToPrune)
            pkg = packagesToPrune{i};
            r = mip.parse.parse_package_arg(pkg);
            if r.is_fqn
                packageDir = mip.paths.get_package_dir(r.org, r.channel, r.name);
            else
                continue  % Skip non-FQN entries (shouldn't happen)
            end

            executeUnload(packageDir, pkg);
            mip.state.key_value_remove('MIP_LOADED_PACKAGES', pkg);
            fprintf('  Pruned package "%s"\n', pkg);
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

    % Find packages to unload (never unload mip itself)
    packagesToUnload = {};
    if forceUnload
        for i = 1:length(MIP_LOADED_PACKAGES)
            pkg = MIP_LOADED_PACKAGES{i};
            if ~strcmp(pkg, 'mip-org/core/mip')
                packagesToUnload{end+1} = pkg; %#ok<AGROW>
            end
        end
    else
        for i = 1:length(MIP_LOADED_PACKAGES)
            pkg = MIP_LOADED_PACKAGES{i};
            if ~ismember(pkg, MIP_STICKY_PACKAGES)
                packagesToUnload{end+1} = pkg; %#ok<AGROW>
            end
        end
    end

    if isempty(packagesToUnload)
        fprintf('No packages to unload\n');
        if ~forceUnload && ~isempty(MIP_STICKY_PACKAGES)
            fprintf('Sticky packages remain: %s\n', strjoin(MIP_STICKY_PACKAGES, ', '));
        end
        return
    end

    if forceUnload
        fprintf('Unloading all packages: %s\n', strjoin(packagesToUnload, ', '));
    else
        if ~isempty(MIP_STICKY_PACKAGES)
            fprintf('Unloading all non-sticky packages: %s\n', strjoin(packagesToUnload, ', '));
        else
            fprintf('Unloading all packages: %s\n', strjoin(packagesToUnload, ', '));
        end
    end

    % Unload each package
    for i = 1:length(packagesToUnload)
        pkg = packagesToUnload{i};
        r = mip.parse.parse_package_arg(pkg);
        if r.is_fqn
            packageDir = mip.paths.get_package_dir(r.org, r.channel, r.name);
        else
            packageDir = fullfile(mip.paths.get_packages_dir(), pkg);
        end
        executeUnload(packageDir, pkg);
        fprintf('  Unloaded package "%s"\n', pkg);
    end

    % Update global variables (mip always remains)
    if forceUnload
        MIP_LOADED_PACKAGES = {'mip-org/core/mip'};
        MIP_DIRECTLY_LOADED_PACKAGES = {};
        MIP_STICKY_PACKAGES = {'mip-org/core/mip'};
    else
        MIP_LOADED_PACKAGES = MIP_STICKY_PACKAGES;
        MIP_DIRECTLY_LOADED_PACKAGES = MIP_DIRECTLY_LOADED_PACKAGES(    ...
            ismember(MIP_DIRECTLY_LOADED_PACKAGES, MIP_STICKY_PACKAGES) ...
        );
    end

    mip.state.key_value_set('MIP_LOADED_PACKAGES', MIP_LOADED_PACKAGES);
    mip.state.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', MIP_DIRECTLY_LOADED_PACKAGES);
    mip.state.key_value_set('MIP_STICKY_PACKAGES', MIP_STICKY_PACKAGES);

    mip.state.check_broken_dependencies('loaded');
end
