function unload(varargin)
%UNLOAD   Unload a mip package from MATLAB path.
%
% Usage:
%   mip.unload('packageName')
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

    % Get package name (first non-flag argument)
    packageArg = '';
    for i = 1:length(varargin)
        if ~startsWith(varargin{i}, '--')
            packageArg = varargin{i};
            break;
        end
    end

    if isempty(packageArg)
        error('mip:noPackage', 'No package name specified for unload command.');
    end

    % Resolve to FQN
    fqn = resolveLoadedFqn(packageArg);

    % mip-org/core/mip cannot be unloaded
    if strcmp(fqn, 'mip') || strcmp(fqn, 'mip-org/core/mip')
        error('mip:cannotUnloadMip', 'Cannot unload mip itself.');
    end

    % Check if package is loaded
    if ~mip.utils.is_loaded(fqn)
        fprintf('Package "%s" is not currently loaded\n', fqn);
        return
    end

    % Get package directory
    result = mip.utils.parse_package_arg(fqn);
    packageDir = mip.utils.get_package_dir(result.org, result.channel, result.name);

    % Execute unload_package.m if it exists
    executeUnload(packageDir, fqn);

    % Remove from sticky packages
    mip.utils.key_value_remove('MIP_STICKY_PACKAGES', fqn);

    % Remove from directly loaded packages
    mip.utils.key_value_remove('MIP_DIRECTLY_LOADED_PACKAGES', fqn);

    % Remove from loaded packages
    mip.utils.key_value_remove('MIP_LOADED_PACKAGES', fqn);

    fprintf('Unloaded package "%s"\n', fqn);

    % Prune packages that are no longer needed
    pruneUnusedPackages();
end

function fqn = resolveLoadedFqn(packageArg)
% Resolve a package argument to its FQN among loaded packages.

    if strcmp(packageArg, 'mip')
        fqn = 'mip';
        return
    end

    result = mip.utils.parse_package_arg(packageArg);

    if result.is_fqn
        fqn = packageArg;
        return
    end

    % Search loaded packages for a bare name match
    loadedPackages = mip.utils.key_value_get('MIP_LOADED_PACKAGES');
    matches = {};
    for i = 1:length(loadedPackages)
        loaded = loadedPackages{i};
        r = mip.utils.parse_package_arg(loaded);
        if r.is_fqn && strcmp(r.name, result.name)
            matches{end+1} = loaded; %#ok<AGROW>
        end
    end

    if isempty(matches)
        fqn = result.name;  % Return bare name; caller will handle "not loaded"
        return
    end

    % Prefer mip-org/core
    for i = 1:length(matches)
        if startsWith(matches{i}, 'mip-org/core/')
            fqn = matches{i};
            return
        end
    end

    matches = sort(matches);
    fqn = matches{1};
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

    MIP_LOADED_PACKAGES          = mip.utils.key_value_get('MIP_LOADED_PACKAGES');
    MIP_DIRECTLY_LOADED_PACKAGES = mip.utils.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');

    if isempty(MIP_LOADED_PACKAGES)
        return
    end

    % Build set of all needed packages (directly loaded + their dependencies)
    neededPackages = {};
    for i = 1:length(MIP_DIRECTLY_LOADED_PACKAGES)
        directPkg = MIP_DIRECTLY_LOADED_PACKAGES{i};
        neededPackages = [neededPackages, getAllDependencies(directPkg)]; %#ok<*AGROW>
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
            r = mip.utils.parse_package_arg(pkg);
            if r.is_fqn
                packageDir = mip.utils.get_package_dir(r.org, r.channel, r.name);
            else
                continue  % Skip non-FQN entries (shouldn't happen)
            end

            executeUnload(packageDir, pkg);
            mip.utils.key_value_remove('MIP_LOADED_PACKAGES', pkg);
            fprintf('  Pruned package "%s"\n', pkg);
        end
    end

    % After pruning, check for broken dependencies
    checkForBrokenDependencies();
end

function deps = getAllDependencies(fqn)
    deps = {};

    result = mip.utils.parse_package_arg(fqn);
    if ~result.is_fqn
        return
    end

    packageDir = mip.utils.get_package_dir(result.org, result.channel, result.name);
    mipJsonPath = fullfile(packageDir, 'mip.json');

    if ~exist(mipJsonPath, 'file')
        return
    end

    try
        fid = fopen(mipJsonPath, 'r');
        jsonText = fread(fid, '*char')';
        fclose(fid);
        mipConfig = jsondecode(jsonText);

        if isfield(mipConfig, 'dependencies') && ~isempty(mipConfig.dependencies)
            depNames = mipConfig.dependencies;
            if ~iscell(depNames)
                depNames = {depNames};
            end
            for i = 1:length(depNames)
                dep = depNames{i};
                % Resolve bare dependency to FQN (same channel first, then core)
                depResult = mip.utils.parse_package_arg(dep);
                if depResult.is_fqn
                    depFqn = dep;
                else
                    % Try same channel first
                    sameDir = mip.utils.get_package_dir(result.org, result.channel, dep);
                    if exist(sameDir, 'dir')
                        depFqn = mip.utils.make_fqn(result.org, result.channel, dep);
                    else
                        depFqn = mip.utils.resolve_bare_name(dep);
                        if isempty(depFqn)
                            continue
                        end
                    end
                end
                if ~ismember(depFqn, deps)
                    deps{end+1} = depFqn;
                    transitiveDeps = getAllDependencies(depFqn);
                    deps = unique([deps, transitiveDeps]);
                end
            end
        end
    catch ME
        warning('mip:jsonParseError', ...
                'Could not parse mip.json for package "%s": %s', ...
                fqn, ME.message);
    end
end

function checkForBrokenDependencies()
    MIP_LOADED_PACKAGES = mip.utils.key_value_get('MIP_LOADED_PACKAGES');

    if isempty(MIP_LOADED_PACKAGES)
        return
    end

    brokenDeps = {};
    for i = 1:length(MIP_LOADED_PACKAGES)
        pkg = MIP_LOADED_PACKAGES{i};
        r = mip.utils.parse_package_arg(pkg);
        if ~r.is_fqn
            continue
        end

        packageDir = mip.utils.get_package_dir(r.org, r.channel, r.name);
        mipJsonPath = fullfile(packageDir, 'mip.json');

        if ~exist(mipJsonPath, 'file')
            continue
        end

        try
            fid = fopen(mipJsonPath, 'r');
            jsonText = fread(fid, '*char')';
            fclose(fid);
            mipConfig = jsondecode(jsonText);

            if isfield(mipConfig, 'dependencies') && ~isempty(mipConfig.dependencies)
                depNames = mipConfig.dependencies;
                if ~iscell(depNames)
                    depNames = {depNames};
                end
                for j = 1:length(depNames)
                    dep = depNames{j};
                    depResult = mip.utils.parse_package_arg(dep);
                    if depResult.is_fqn
                        depFqn = dep;
                    else
                        depFqn = mip.utils.resolve_bare_name(dep);
                    end
                    if isempty(depFqn) || ~mip.utils.is_loaded(depFqn)
                        brokenDeps{end+1} = sprintf('Package "%s" depends on "%s" which is no longer loaded', pkg, dep); %#ok<AGROW>
                    end
                end
            end
        catch
            % Silently ignore parse errors
        end
    end

    if ~isempty(brokenDeps)
        warning('mip:brokenDependencies', ...
                'Warning: Some loaded packages have missing dependencies:\n  %s', ...
                strjoin(brokenDeps, '\n  '));
    end
end

function unloadAll(forceUnload)
    MIP_LOADED_PACKAGES          = mip.utils.key_value_get('MIP_LOADED_PACKAGES');
    MIP_DIRECTLY_LOADED_PACKAGES = mip.utils.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
    MIP_STICKY_PACKAGES          = mip.utils.key_value_get('MIP_STICKY_PACKAGES');

    if isempty(MIP_LOADED_PACKAGES)
        fprintf('No packages are currently loaded\n');
        return
    end

    % Find packages to unload (never unload mip itself)
    packagesToUnload = {};
    if forceUnload
        for i = 1:length(MIP_LOADED_PACKAGES)
            pkg = MIP_LOADED_PACKAGES{i};
            if ~strcmp(pkg, 'mip') && ~strcmp(pkg, 'mip-org/core/mip')
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
        r = mip.utils.parse_package_arg(pkg);
        if r.is_fqn
            packageDir = mip.utils.get_package_dir(r.org, r.channel, r.name);
        else
            packageDir = fullfile(mip.utils.get_packages_dir(), pkg);
        end
        executeUnload(packageDir, pkg);
        fprintf('  Unloaded package "%s"\n', pkg);
    end

    % Update global variables (mip always remains)
    if forceUnload
        MIP_LOADED_PACKAGES = {'mip'};
        MIP_DIRECTLY_LOADED_PACKAGES = {};
        MIP_STICKY_PACKAGES = {'mip'};
    else
        MIP_LOADED_PACKAGES = MIP_STICKY_PACKAGES;
        MIP_DIRECTLY_LOADED_PACKAGES = MIP_DIRECTLY_LOADED_PACKAGES(    ...
            ismember(MIP_DIRECTLY_LOADED_PACKAGES, MIP_STICKY_PACKAGES) ...
        );
    end

    mip.utils.key_value_set('MIP_LOADED_PACKAGES', MIP_LOADED_PACKAGES);
    mip.utils.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', MIP_DIRECTLY_LOADED_PACKAGES);
    mip.utils.key_value_set('MIP_STICKY_PACKAGES', MIP_STICKY_PACKAGES);

    checkForBrokenDependencies();
end
