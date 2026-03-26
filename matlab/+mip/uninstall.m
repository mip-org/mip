function uninstall(varargin)
%UNINSTALL   Uninstall one or more mip packages.
%
% Usage:
%   mip.uninstall('packageName')
%   mip.uninstall('package1', 'package2', 'package3')
%
% Args:
%   Package name(s) to uninstall, as strings or char arrays.
%
% This function uninstalls packages and then prunes any packages that
% are no longer needed (packages that were installed as dependencies
% but are not dependencies of any directly installed package).

    if nargin < 1
        error('mip:uninstall:noPackage', ...
              'At least one package name is required for uninstall command.');
    end

    packageNames = varargin;

    % mip cannot be uninstalled via this command
    if any(strcmp(packageNames, 'mip'))
        fprintf('Cannot uninstall mip via "mip uninstall".\n');
        fprintf('To uninstall mip manually:\n');
        fprintf('  1. Remove the mip directory: %s\n', mip.root());
        fprintf('  2. Remove the mip entry from your MATLAB path (e.g., using pathtool)\n');
        packageNames = packageNames(~strcmp(packageNames, 'mip'));
        if isempty(packageNames)
            return
        end
    end

    packagesDir = mip.utils.get_packages_dir();

    % Check which requested packages are installed
    notInstalled = {};
    requestedPackages = {};

    for i = 1:length(packageNames)
        pkgName = packageNames{i};
        pkgDir = fullfile(packagesDir, pkgName);
        if ~exist(pkgDir, 'dir')
            notInstalled = [notInstalled, {pkgName}]; %#ok<*AGROW>
        else
            requestedPackages = [requestedPackages, {pkgName}];
        end
    end

    % Report packages that aren't installed
    for i = 1:length(notInstalled)
        fprintf('Package "%s" is not installed\n', notInstalled{i});
    end

    % If no valid packages to uninstall, return
    if isempty(requestedPackages)
        return
    end

    % Confirm uninstallation
    if length(requestedPackages) == 1
        response = input(sprintf('Are you sure you want to uninstall "%s"? (y/n): ', requestedPackages{1}), 's');
    else
        response = input(sprintf('Are you sure you want to uninstall these %d packages? (y/n): ', length(requestedPackages)), 's');
    end

    if ~strcmpi(response, 'y') && ~strcmpi(response, 'yes')
        fprintf('Uninstallation cancelled\n');
        return
    end

    % Uninstall each requested package
    fprintf('\n');
    for i = 1:length(requestedPackages)
        pkg = requestedPackages{i};
        pkgDir = fullfile(packagesDir, pkg);
        
        try
            fprintf('Uninstalling "%s"...\n', pkg);
            rmdir(pkgDir, 's');
            fprintf('Uninstalled package "%s"\n', pkg);
        catch ME
            error('mip:uninstallFailed', ...
                  'Failed to uninstall package "%s": %s', pkg, ME.message);
        end
        
        % Remove from directly installed packages and channel tracking
        mip.utils.remove_directly_installed(pkg);
        mip.utils.remove_package_channel(pkg);
    end

    % Prune packages that are no longer needed
    pruneUnusedPackages(packagesDir);
end

function pruneUnusedPackages(packagesDir)
% Prune packages that are no longer needed
% A package is needed if it is:
% 1. Directly installed by the user, OR
% 2. A dependency of a directly installed package

    % Get all installed packages
    installedPackages = {};
    if exist(packagesDir, 'dir')
        dirContents = dir(packagesDir);
        for i = 1:length(dirContents)
            if dirContents(i).isdir && ~startsWith(dirContents(i).name, '.')
                installedPackages{end+1} = dirContents(i).name; %#ok<*AGROW>
            end
        end
    end
    
    if isempty(installedPackages)
        return
    end
    
    directlyInstalled = mip.utils.get_directly_installed();
    
    % Build set of all needed packages (directly installed + their dependencies)
    neededPackages = {};
    for i = 1:length(directlyInstalled)
        directPkg = directlyInstalled{i};
        % Only consider if the package is still installed
        if ismember(directPkg, installedPackages)
            neededPackages = [neededPackages, getAllDependencies(directPkg, packagesDir, {})];
        end
    end
    
    % Add directly installed packages themselves
    neededPackages = unique([directlyInstalled, neededPackages]);
    
    % Find packages to prune (installed but not needed)
    packagesToPrune = {};
    for i = 1:length(installedPackages)
        pkg = installedPackages{i};
        if ~ismember(pkg, neededPackages)
            packagesToPrune{end+1} = pkg;
        end
    end
    
    % Prune each unnecessary package
    if ~isempty(packagesToPrune)
        fprintf('\nPruning unnecessary packages: %s\n', strjoin(packagesToPrune, ', '));
        for i = 1:length(packagesToPrune)
            pkg = packagesToPrune{i};
            packageDir = fullfile(packagesDir, pkg);
            
            try
                rmdir(packageDir, 's');
                mip.utils.remove_package_channel(pkg);
                fprintf('  Pruned package "%s"\n', pkg);
            catch ME
                warning('mip:pruneFailed', ...
                        'Failed to prune package "%s": %s', pkg, ME.message);
            end
        end
    end
    
    % After pruning, check for broken dependencies
    checkForBrokenDependencies(packagesDir);
end

function deps = getAllDependencies(packageName, packagesDir, visited)
    % Recursively get all dependencies of a package
    % visited: cell array of package names already being processed to prevent infinite recursion
    deps = {};

    % Prevent infinite recursion by tracking visited packages
    if ismember(packageName, visited)
        return
    end
    
    visited = [visited, {packageName}];

    packageDir = fullfile(packagesDir, packageName);
    mipJsonPath = fullfile(packageDir, 'mip.json');

    if ~exist(mipJsonPath, 'file')
        return
    end

    try
        % Read and parse mip.json
        fid = fopen(mipJsonPath, 'r');
        jsonText = fread(fid, '*char')';
        fclose(fid);
        mipConfig = jsondecode(jsonText);

        % Get direct dependencies
        if isfield(mipConfig, 'dependencies') && ~isempty(mipConfig.dependencies)
            for i = 1:length(mipConfig.dependencies)
                dep = mipConfig.dependencies{i};
                if ~ismember(dep, deps)
                    deps{end+1} = dep;
                    % Recursively get dependencies of this dependency
                    transitiveDeps = getAllDependencies(dep, packagesDir, visited);
                    deps = unique([deps, transitiveDeps]);
                end
            end
        end
    catch ME
        warning('mip:jsonParseError', ...
                'Could not parse mip.json for package "%s": %s', ...
                packageName, ME.message);
    end
end

function checkForBrokenDependencies(packagesDir)
% Check if any installed packages now have missing dependencies
% and warn the user

    % Get all installed packages
    installedPackages = {};
    if exist(packagesDir, 'dir')
        dirContents = dir(packagesDir);
        for i = 1:length(dirContents)
            if dirContents(i).isdir && ~startsWith(dirContents(i).name, '.')
                installedPackages{end+1} = dirContents(i).name; %#ok<*AGROW>
            end
        end
    end
    
    if isempty(installedPackages)
        return
    end

    % Check each installed package for broken dependencies
    brokenDeps = {};
    for i = 1:length(installedPackages)
        pkg = installedPackages{i};
        packageDir = fullfile(packagesDir, pkg);
        mipJsonPath = fullfile(packageDir, 'mip.json');
        
        if ~exist(mipJsonPath, 'file')
            continue
        end
        
        try
            % Read and parse mip.json
            fid = fopen(mipJsonPath, 'r');
            jsonText = fread(fid, '*char')';
            fclose(fid);
            mipConfig = jsondecode(jsonText);
            
            % Check if any dependencies are missing (not installed)
            if isfield(mipConfig, 'dependencies') && ~isempty(mipConfig.dependencies)
                for j = 1:length(mipConfig.dependencies)
                    dep = mipConfig.dependencies{j};
                    if ~ismember(dep, installedPackages)
                        brokenDeps{end+1} = sprintf('Package "%s" depends on "%s" which is no longer installed', pkg, dep);
                    end
                end
            end
        catch ME
            % Silently ignore parse errors (already warned elsewhere)
        end
    end
    
    % Warn about broken dependencies
    if ~isempty(brokenDeps)
        warning('mip:brokenDependencies', ...
                'Warning: Some installed packages have missing dependencies:\n  %s', ...
                strjoin(brokenDeps, '\n  '));
    end
end
