function install(varargin)
%INSTALL   Install one or more mip packages.
%
% Usage:
%   mip.install('packageName')
%   mip.install('package1', 'package2', 'package3')
%   mip.install('--channel', 'dev', 'packageName')
%   mip.install('/path/to/package.mhl')
%   mip.install('https://example.com/package.mhl')
%
% Options:
%   --channel <name>  Install from a specific channel (default: core)
%
% Args:
%   Package name(s), .mhl file path(s), or URL(s), as strings or char arrays.
%
% This function installs packages from the mip repository, local .mhl files,
% or URLs. Dependencies are automatically resolved and installed.

    if nargin < 1
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    [channel, args] = mip.utils.parse_channel_flag(varargin);

    if isempty(args)
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    packageNames = args;
    packagesDir = mip.utils.get_packages_dir();

    % Create packages directory if it doesn't exist
    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    % Separate packages by type
    repoPackages = {};
    mhlSources = {};

    for i = 1:length(packageNames)
        pkg = packageNames{i};
        if endsWith(pkg, '.mhl') || startsWith(pkg, 'http://') || startsWith(pkg, 'https://')
            mhlSources = [mhlSources, {pkg}]; %#ok<*AGROW>
        else
            repoPackages = [repoPackages, {pkg}];
        end
    end

    % Handle repository packages
    installedCount = 0;

    if ~isempty(repoPackages)
        installedCount = installedCount + installFromRepository(repoPackages, packagesDir, channel);
    end

    % Handle .mhl file installations
    for i = 1:length(mhlSources)
        if installFromMhl(mhlSources{i}, packagesDir)
            installedCount = installedCount + 1;
        end
    end

    % Summary
    if installedCount == 0 && isempty(mhlSources)
        fprintf('\nAll packages already installed.\n');
    elseif installedCount > 0
        fprintf('\nSuccessfully installed %d package(s).\n', installedCount);
    end
end

function count = installFromRepository(repoPackages, packagesDir, channel)
% Install packages from the mip repository

    count = 0;

    try
        % Download and parse package index
        if ~isempty(channel)
            fprintf('Using channel: %s\n', channel);
        end
        fprintf('Fetching package index...\n');

        index = mip.utils.fetch_index(channel);

        % Get current architecture
        currentArch = mip.arch();
        fprintf('Detected architecture: %s\n', currentArch);

        % Build package info map
        [packageInfoMap, unavailablePackages] = mip.utils.build_package_info_map(index);

        % Check if any requested packages are unavailable
        for i = 1:length(repoPackages)
            pkgName = repoPackages{i};
            if ~packageInfoMap.isKey(pkgName)
                if unavailablePackages.isKey(pkgName)
                    archs = unavailablePackages(pkgName);
                    fprintf('\nError: Package "%s" is not available for architecture "%s"\n', ...
                            pkgName, currentArch);
                    fprintf('Available architectures: %s\n', strjoin(archs, ', '));
                    error('mip:packageUnavailable', 'Package not available for this architecture');
                else
                    error('mip:packageNotFound', ...
                          'Package "%s" not found in repository', pkgName);
                end
            end
        end

        % Resolve dependencies
        if length(repoPackages) == 1
            fprintf('Resolving dependencies for "%s"...\n', repoPackages{1});
        else
            fprintf('Resolving dependencies for %d packages...\n', length(repoPackages));
        end

        % Build combined dependency graph
        allRequired = {};
        for i = 1:length(repoPackages)
            pkgName = repoPackages{i};
            installOrder = mip.dependency.build_dependency_graph(pkgName, packageInfoMap);
            allRequired = [allRequired, installOrder];
        end
        allRequired = unique(allRequired, 'stable');

        % Sort topologically
        allPackagesToInstall = mip.dependency.topological_sort(allRequired, packageInfoMap);

        % Filter out already installed packages
        toInstall = {};
        alreadyInstalled = {};

        for i = 1:length(allPackagesToInstall)
            pkgName = allPackagesToInstall{i};
            pkgDir = fullfile(packagesDir, pkgName);
            if exist(pkgDir, 'dir')
                alreadyInstalled = [alreadyInstalled, {pkgName}];
            else
                toInstall = [toInstall, {pkgName}];
            end
        end

        % Report already installed packages
        for i = 1:length(alreadyInstalled)
            fprintf('Package "%s" is already installed\n', alreadyInstalled{i});
        end

        % Show installation plan
        if ~isempty(toInstall)
            if length(toInstall) == 1
                fprintf('\nInstallation plan:\n');
            else
                fprintf('\nInstallation plan (%d packages):\n', length(toInstall));
            end

            for i = 1:length(toInstall)
                pkgName = toInstall{i};
                pkgInfo = packageInfoMap(pkgName);
                fprintf('  - %s %s\n', pkgName, pkgInfo.version);
            end
            fprintf('\n');

            % Install each package
            for i = 1:length(toInstall)
                pkgName = toInstall{i};
                pkgInfo = packageInfoMap(pkgName);
                downloadAndInstall(pkgName, pkgInfo, packagesDir);
                count = count + 1;
            end
            
            % Mark requested packages as directly installed and record channel
            effectiveChannel = channel;
            if isempty(effectiveChannel)
                effectiveChannel = 'core';
            end
            for i = 1:length(toInstall)
                mip.utils.set_package_channel(toInstall{i}, effectiveChannel);
            end
            for i = 1:length(repoPackages)
                mip.utils.add_directly_installed(repoPackages{i});
            end
        end

    catch ME
        rethrow(ME);
    end
end

function success = installFromMhl(mhlSource, packagesDir)
% Install a package from a local .mhl file or URL

    success = false;
    tempDir = tempname;
    mkdir(tempDir);

    try
        % Download or copy the .mhl file
        mhlPath = mip.utils.download_mhl(mhlSource, tempDir);

        % Extract the .mhl file
        extractDir = fullfile(tempDir, 'extracted');
        mip.utils.extract_mhl(mhlPath, extractDir);

        % Read mip.json to get package name and dependencies
        pkgInfo = mip.utils.read_package_json(extractDir);
        packageName = pkgInfo.name;

        % Check if package is already installed
        pkgDir = fullfile(packagesDir, packageName);
        if exist(pkgDir, 'dir')
            fprintf('Package "%s" is already installed\n', packageName);
            return
        end

        % Install dependencies from remote repository if any
        if ~isempty(pkgInfo.dependencies)
            fprintf('\nPackage "%s" has dependencies: %s\n', ...
                    packageName, strjoin(pkgInfo.dependencies, ', '));
            fprintf('Installing dependencies from remote repository...\n');
            installFromRepository(pkgInfo.dependencies, packagesDir);
        end

        % Install the package
        fprintf('\nInstalling "%s"...\n', packageName);

        % Move extracted files to packages directory
        movefile(extractDir, pkgDir);

        fprintf('Successfully installed "%s"\n', packageName);
        
        % Mark as directly installed
        mip.utils.add_directly_installed(packageName);
        
        success = true;

    catch ME
        % Clean up on error
        if exist(tempDir, 'dir')
            rmdir(tempDir, 's');
        end
        rethrow(ME);
    end

    % Clean up temp directory
    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
    end
end

function downloadAndInstall(packageName, packageInfo, packagesDir)
% Download and install a single package

    mhlUrl = packageInfo.mhl_url;
    fprintf('Downloading %s %s...\n', packageName, packageInfo.version);

    tempDir = tempname;
    mkdir(tempDir);

    try
        % Download .mhl file
        mhlPath = mip.utils.download_mhl(mhlUrl, tempDir);

        % Extract to package directory
        pkgDir = fullfile(packagesDir, packageName);
        mip.utils.extract_mhl(mhlPath, pkgDir);

        fprintf('Successfully installed "%s"\n', packageName);

    catch ME
        % Clean up on error
        if exist(tempDir, 'dir')
            rmdir(tempDir, 's');
        end
        if exist(pkgDir, 'dir')
            rmdir(pkgDir, 's');
        end
        rethrow(ME);
    end

    % Clean up temp directory
    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
    end
end

function bestVariant = selectBestVariant(variants, currentArch)
% Select the best package variant for the current architecture

    if isempty(variants)
        bestVariant = [];
        return
    end

    % Filter to compatible variants (exact match or 'any')
    compatible = {};
    for i = 1:length(variants)
        v = variants{i};
        % Access architecture field safely
        if isfield(v, 'architecture')
            arch = v.architecture;
        else
            % Skip variants without architecture field
            continue
        end

        if strcmp(arch, currentArch) || strcmp(arch, 'any')
            compatible = [compatible, {v}];
        end
    end

    if isempty(compatible)
        bestVariant = [];
        return
    end

    % Prefer exact architecture matches over 'any'
    exactMatches = {};
    for i = 1:length(compatible)
        v = compatible{i};
        arch = v.architecture;
        if strcmp(arch, currentArch)
            exactMatches = [exactMatches, {v}];
        end
    end

    if ~isempty(exactMatches)
        bestVariant = selectLatest(exactMatches);
    else
        bestVariant = selectLatest(compatible);
    end
end

function best = selectLatest(variants)
% Select the variant with the latest version from a list of variants
    best = variants{1};
    for i = 2:length(variants)
        if mip.utils.compare_versions(variants{i}.version, best.version) > 0
            best = variants{i};
        end
    end
end
