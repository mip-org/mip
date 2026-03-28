function uninstall(varargin)
%UNINSTALL   Uninstall one or more mip packages.
%
% Usage:
%   mip.uninstall('packageName')
%   mip.uninstall('org/channel/packageName')
%   mip.uninstall('package1', 'package2')
%
% Accepts both bare package names and fully qualified names.
% This function uninstalls packages and then prunes any packages that
% are no longer needed (packages that were installed as dependencies
% but are not dependencies of any directly installed package).

    if nargin < 1
        error('mip:uninstall:noPackage', ...
              'At least one package name is required for uninstall command.');
    end

    packageArgs = varargin;

    % mip-org/core/mip cannot be uninstalled via this command
    hasMip = false;
    for i = 1:length(packageArgs)
        if strcmp(packageArgs{i}, 'mip') || strcmp(packageArgs{i}, 'mip-org/core/mip')
            hasMip = true;
            break;
        end
    end
    if hasMip
        fprintf('Cannot uninstall mip via "mip uninstall".\n');
        fprintf('To uninstall mip manually:\n');
        fprintf('  1. Remove the mip directory: %s\n', mip.root());
        fprintf('  2. Remove the mip entry from your MATLAB path (e.g., using pathtool)\n');
        packageArgs = packageArgs(~strcmp(packageArgs, 'mip'));
        if isempty(packageArgs)
            return
        end
    end

    % Resolve all package arguments to FQNs
    notInstalled = {};
    resolvedPackages = {};

    for i = 1:length(packageArgs)
        arg = packageArgs{i};
        result = mip.utils.parse_package_arg(arg);

        if result.is_fqn
            fqn = arg;
            pkgDir = mip.utils.get_package_dir(result.org, result.channel, result.name);
        else
            fqn = mip.utils.resolve_bare_name(result.name);
            if isempty(fqn)
                notInstalled = [notInstalled, {arg}]; %#ok<*AGROW>
                continue
            end
            r = mip.utils.parse_package_arg(fqn);
            pkgDir = mip.utils.get_package_dir(r.org, r.channel, r.name);
        end

        if ~exist(pkgDir, 'dir')
            notInstalled = [notInstalled, {arg}];
        else
            resolvedPackages = [resolvedPackages, {fqn}];
        end
    end

    % Report packages that aren't installed
    for i = 1:length(notInstalled)
        fprintf('Package "%s" is not installed\n', notInstalled{i});
    end

    if isempty(resolvedPackages)
        return
    end

    % Confirm uninstallation
    if length(resolvedPackages) == 1
        response = input(sprintf('Are you sure you want to uninstall "%s"? (y/n): ', resolvedPackages{1}), 's');
    else
        response = input(sprintf('Are you sure you want to uninstall these %d packages? (y/n): ', length(resolvedPackages)), 's');
    end

    if ~strcmpi(response, 'y') && ~strcmpi(response, 'yes')
        fprintf('Uninstallation cancelled\n');
        return
    end

    % Uninstall each requested package
    fprintf('\n');
    for i = 1:length(resolvedPackages)
        fqn = resolvedPackages{i};
        r = mip.utils.parse_package_arg(fqn);
        pkgDir = mip.utils.get_package_dir(r.org, r.channel, r.name);

        try
            fprintf('Uninstalling "%s"...\n', fqn);
            rmdir(pkgDir, 's');
            fprintf('Uninstalled package "%s"\n', fqn);
        catch ME
            error('mip:uninstallFailed', ...
                  'Failed to uninstall package "%s": %s', fqn, ME.message);
        end

        % Remove from directly installed packages
        mip.utils.remove_directly_installed(fqn);

        % Clean up empty parent directories
        cleanupEmptyDirs(fullfile(mip.utils.get_packages_dir(), r.org, r.channel));
        cleanupEmptyDirs(fullfile(mip.utils.get_packages_dir(), r.org));
    end

    % Prune packages that are no longer needed
    pruneUnusedPackages();
end

function cleanupEmptyDirs(dirPath)
% Remove directory if it is empty (no subdirectories or files)
    if ~exist(dirPath, 'dir')
        return
    end
    contents = dir(dirPath);
    % Filter out . and ..
    contents = contents(~ismember({contents.name}, {'.', '..'}));
    if isempty(contents)
        rmdir(dirPath);
    end
end

function pruneUnusedPackages()
% Prune packages that are no longer needed

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
            neededPackages = [neededPackages, getAllDependencies(directPkg)]; %#ok<AGROW>
        end
    end

    neededPackages = unique([directlyInstalled, neededPackages]);

    % Find packages to prune (installed but not needed)
    % Never prune mip-org/core/mip - it is the package manager itself
    packagesToPrune = {};
    for i = 1:length(allInstalled)
        fqn = allInstalled{i};
        if ~ismember(fqn, neededPackages) && ~strcmp(fqn, 'mip-org/core/mip')
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
                cleanupEmptyDirs(fullfile(mip.utils.get_packages_dir(), r.org, r.channel));
                cleanupEmptyDirs(fullfile(mip.utils.get_packages_dir(), r.org));
            catch ME
                warning('mip:pruneFailed', ...
                        'Failed to prune package "%s": %s', fqn, ME.message);
            end
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

    pkgDir = mip.utils.get_package_dir(result.org, result.channel, result.name);
    mipJsonPath = fullfile(pkgDir, 'mip.json');

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
                depResult = mip.utils.parse_package_arg(dep);
                if depResult.is_fqn
                    depFqn = dep;
                else
                    % Same channel first, then resolve
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
                    deps{end+1} = depFqn; %#ok<AGROW>
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
    allInstalled = mip.utils.list_installed_packages();

    if isempty(allInstalled)
        return
    end

    brokenDeps = {};
    for i = 1:length(allInstalled)
        fqn = allInstalled{i};
        r = mip.utils.parse_package_arg(fqn);
        pkgDir = mip.utils.get_package_dir(r.org, r.channel, r.name);
        mipJsonPath = fullfile(pkgDir, 'mip.json');

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
                        depR = mip.utils.parse_package_arg(dep);
                        depDir = mip.utils.get_package_dir(depR.org, depR.channel, depR.name);
                        if ~exist(depDir, 'dir')
                            brokenDeps{end+1} = sprintf('Package "%s" depends on "%s" which is not installed', fqn, dep); %#ok<AGROW>
                        end
                    else
                        resolved = mip.utils.resolve_bare_name(dep);
                        if isempty(resolved)
                            brokenDeps{end+1} = sprintf('Package "%s" depends on "%s" which is not installed', fqn, dep); %#ok<AGROW>
                        end
                    end
                end
            end
        catch
        end
    end

    if ~isempty(brokenDeps)
        warning('mip:brokenDependencies', ...
                'Warning: Some installed packages have missing dependencies:\n  %s', ...
                strjoin(brokenDeps, '\n  '));
    end
end
