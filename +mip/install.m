function install(varargin)
%INSTALL   Install one or more mip packages.
%
% Usage:
%   mip.install('packageName')
%   mip.install('package1', 'package2', 'package3')
%   mip.install('--channel', 'dev', 'packageName')
%   mip.install('--channel', 'owner/chan', 'packageName')
%   mip.install('owner/chan/packageName')
%   mip.install('/path/to/package.mhl')
%   mip.install('https://example.com/package.mhl')
%   mip.install('/path/to/local/package')          - Install from local directory
%   mip.install('.', '--editable')                  - Editable install (like pip -e)
%   mip.install('-e', '/path/to/package')           - Editable install (short form)
%
% Options:
%   --channel <name>    Install from a specific channel (default: core)
%                       Accepts 'core', 'dev', or 'owner/channel'
%   --editable, -e      Install in editable mode (local packages only)
%
% Local packages:
%   If the argument is a directory path containing a mip.yaml file,
%   the package is installed locally. In editable mode, changes to
%   the source directory are reflected immediately without reinstalling.
%
% Packages can be specified by bare name or fully qualified name
% (org/channel/package). Fully qualified names override the --channel flag.

    if nargin < 1
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Check for --editable / -e flag
    editable = false;
    filteredArgs = {};
    for i = 1:length(varargin)
        arg = varargin{i};
        if ischar(arg) && (strcmp(arg, '--editable') || strcmp(arg, '-e'))
            editable = true;
        else
            filteredArgs{end+1} = arg;
        end
    end

    [channel, args] = mip.utils.parse_channel_flag(filteredArgs);

    if isempty(args)
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Check if any argument is a local directory with mip.yaml
    for i = 1:length(args)
        pkg = args{i};
        % Resolve '.' and relative paths
        if exist(pkg, 'dir')
            mipYamlPath = fullfile(pkg, 'mip.yaml');
            if exist(mipYamlPath, 'file')
                mip.utils.install_local(pkg, editable);
                return;
            else
                error('mip:install:noMipYaml', ...
                      'Directory "%s" does not contain a mip.yaml file.', pkg);
            end
        end
    end

    if editable
        error('mip:install:editableRequiresLocal', ...
              '--editable can only be used with local directory packages.');
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
    installedFqns = {};

    if ~isempty(repoPackages)
        installedFqns = [installedFqns, installFromRepository(repoPackages, packagesDir, channel)];
    end

    % Handle .mhl file installations
    for i = 1:length(mhlSources)
        fqn = installFromMhl(mhlSources{i}, packagesDir, channel);
        if ~isempty(fqn)
            installedFqns = [installedFqns, {fqn}];
        end
    end

    % Summary
    installedCount = length(installedFqns);
    if installedCount == 0 && isempty(mhlSources)
        fprintf('\nAll packages already installed.\n');
    elseif installedCount > 0
        fprintf('\nSuccessfully installed %d package(s).\n', installedCount);
        fprintf('\nTo use installed packages, run:\n');
        for i = 1:length(installedFqns)
            fprintf('  mip load %s\n', loadHintName(installedFqns{i}));
        end
    end
end

function installedFqns = installFromRepository(repoPackages, ~, channel)
% Install packages from the mip repository

    installedFqns = {};

    % Determine effective channel for bare-name packages
    if isempty(channel)
        channel = 'core';
    end

    [defaultOrg, defaultChan] = mip.utils.parse_channel_spec(channel);

    fprintf('Using channel: %s/%s\n', defaultOrg, defaultChan);
    fprintf('Fetching package index...\n');

    % Fetch the primary channel index
    index = mip.utils.fetch_index(channel);

    % Get current architecture
    currentArch = mip.arch();
    fprintf('Detected architecture: %s\n', currentArch);

    % Resolve each package argument to org/channel/name (with optional version)
    % The --channel flag only applies to user-specified bare names, not dependencies
    resolvedPackages = {};  % cell array of structs with .org, .channel, .name, .fqn
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:length(repoPackages)
        pkg = repoPackages{i};
        [org, ch, name, version] = mip.utils.resolve_package_name(pkg, channel);
        s = struct('org', org, 'channel', ch, 'name', name, ...
                   'fqn', mip.utils.make_fqn(org, ch, name));
        resolvedPackages{end+1} = s;
        if ~isempty(version)
            requestedVersions(name) = version;
        end
    end

    % Build package info map
    isCore = strcmp(defaultOrg, 'mip-org') && strcmp(defaultChan, 'core');
    if isCore
        % Core channel: single index with version constraints
        [packageInfoMap, unavailablePackages] = mip.utils.build_package_info_map(index, defaultOrg, defaultChan, requestedVersions);
    else
        % Non-core channel: also fetch core index for dependency resolution
        % (bare-name dependencies always resolve to mip-org/core)
        fprintf('Fetching core package index for dependency resolution...\n');
        coreIndex = mip.utils.fetch_index('core');
        [packageInfoMap, unavailablePackages] = mip.utils.build_package_info_map(coreIndex, 'mip-org', 'core');

        % Add channel packages (version constraints only apply to these)
        [channelMap, channelUnavail] = mip.utils.build_package_info_map(index, defaultOrg, defaultChan, requestedVersions);
        channelKeys = keys(channelMap);
        for i = 1:length(channelKeys)
            packageInfoMap(channelKeys{i}) = channelMap(channelKeys{i});
        end
        channelUnavailKeys = keys(channelUnavail);
        for i = 1:length(channelUnavailKeys)
            unavailablePackages(channelUnavailKeys{i}) = channelUnavail(channelUnavailKeys{i});
        end
    end

    % Check if any requested packages are unavailable
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        if ~packageInfoMap.isKey(s.fqn)
            if unavailablePackages.isKey(s.fqn)
                archs = unavailablePackages(s.fqn);
                fprintf('\nError: Package "%s" is not available for architecture "%s"\n', ...
                        s.fqn, currentArch);
                fprintf('Available architectures: %s\n', strjoin(archs, ', '));
                error('mip:packageUnavailable', 'Package not available for this architecture');
            else
                error('mip:packageNotFound', ...
                      'Package "%s" not found in repository', s.fqn);
            end
        end
    end

    % Resolve dependencies
    if length(resolvedPackages) == 1
        fprintf('Resolving dependencies for "%s"...\n', resolvedPackages{1}.fqn);
    else
        fprintf('Resolving dependencies for %d packages...\n', length(resolvedPackages));
    end

    % Build combined dependency graph
    allRequiredFqns = {};
    for i = 1:length(resolvedPackages)
        installOrder = mip.dependency.build_dependency_graph(resolvedPackages{i}.fqn, packageInfoMap);
        allRequiredFqns = [allRequiredFqns, installOrder];
    end
    allRequiredFqns = unique(allRequiredFqns, 'stable');

    % Sort topologically
    allPackagesToInstall = mip.dependency.topological_sort(allRequiredFqns, packageInfoMap);

    % Determine which packages need installing vs already installed
    toInstallFqns = {};
    alreadyInstalled = {};

    for i = 1:length(allPackagesToInstall)
        fqn = allPackagesToInstall{i};
        result = mip.utils.parse_package_arg(fqn);
        pkgDir = mip.utils.get_package_dir(result.org, result.channel, result.name);

        if exist(pkgDir, 'dir')
            alreadyInstalled{end+1} = fqn;
        else
            toInstallFqns{end+1} = fqn;
        end
    end

    % Report already installed packages
    for i = 1:length(alreadyInstalled)
        fprintf('Package "%s" is already installed\n', alreadyInstalled{i});
    end

    % Show installation plan
    if ~isempty(toInstallFqns)
        if length(toInstallFqns) == 1
            fprintf('\nInstallation plan:\n');
        else
            fprintf('\nInstallation plan (%d packages):\n', length(toInstallFqns));
        end

        for i = 1:length(toInstallFqns)
            fqn = toInstallFqns{i};
            pkgInfo = packageInfoMap(fqn);
            fprintf('  - %s %s\n', fqn, pkgInfo.version);
        end
        fprintf('\n');

        % Install each package
        for i = 1:length(toInstallFqns)
            fqn = toInstallFqns{i};
            pkgInfo = packageInfoMap(fqn);
            result = mip.utils.parse_package_arg(fqn);
            pkgDir = mip.utils.get_package_dir(result.org, result.channel, result.name);
            downloadAndInstall(fqn, pkgInfo, pkgDir);
        end

        % Mark requested packages as directly installed and collect their FQNs
        for i = 1:length(resolvedPackages)
            s = resolvedPackages{i};
            mip.utils.add_directly_installed(s.fqn);
            if ismember(s.fqn, toInstallFqns)
                installedFqns{end+1} = s.fqn;
            end
        end
    end

    % Warn if any installed package name exists in multiple channels
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        allInstalled = mip.utils.find_all_installed_by_name(s.name);
        if length(allInstalled) > 1
            fprintf('\nWarning: Package "%s" is installed from multiple channels:\n', s.name);
            for k = 1:length(allInstalled)
                fprintf('  - %s\n', allInstalled{k});
            end
        end
    end

end

function installedFqn = installFromMhl(mhlSource, packagesDir, channel)
% Install a package from a local .mhl file or URL

    installedFqn = '';
    tempDir = tempname;
    mkdir(tempDir);

    if isempty(channel)
        channel = 'core';
    end
    [org, channelName] = mip.utils.parse_channel_spec(channel);

    try
        % Download or copy the .mhl file
        mhlPath = mip.utils.download_mhl(mhlSource, tempDir);

        % Extract the .mhl file
        extractDir = fullfile(tempDir, 'extracted');
        mip.utils.extract_mhl(mhlPath, extractDir);

        % Read mip.json to get package name and dependencies
        pkgInfo = mip.utils.read_package_json(extractDir);
        packageName = pkgInfo.name;
        fqn = mip.utils.make_fqn(org, channelName, packageName);

        % Check if package is already installed
        pkgDir = mip.utils.get_package_dir(org, channelName, packageName);
        if exist(pkgDir, 'dir')
            fprintf('Package "%s" is already installed\n', fqn);
            return
        end

        % Install dependencies from remote repository if any
        if ~isempty(pkgInfo.dependencies)
            fprintf('\nPackage "%s" has dependencies: %s\n', ...
                    fqn, strjoin(pkgInfo.dependencies, ', '));
            fprintf('Installing dependencies from remote repository...\n');
            installFromRepository(pkgInfo.dependencies, packagesDir, channel);
        end

        % Install the package
        fprintf('\nInstalling "%s"...\n', fqn);

        % Create parent directories if needed
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end

        % Move extracted files to packages directory
        movefile(extractDir, pkgDir);

        fprintf('Successfully installed "%s"\n', fqn);

        % Mark as directly installed
        mip.utils.add_directly_installed(fqn);

        installedFqn = fqn;

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

function name = loadHintName(fqn)
% Return bare name if unique across installed packages, otherwise FQN.
    result = mip.utils.parse_package_arg(fqn);
    allInstalled = mip.utils.list_installed_packages();
    count = 0;
    for i = 1:length(allInstalled)
        r = mip.utils.parse_package_arg(allInstalled{i});
        if strcmp(r.name, result.name)
            count = count + 1;
        end
    end
    if count > 1
        name = fqn;
    else
        name = result.name;
    end
end

function downloadAndInstall(fqn, packageInfo, pkgDir)
% Download and install a single package

    mhlUrl = packageInfo.mhl_url;
    fprintf('Downloading %s %s...\n', fqn, packageInfo.version);

    tempDir = tempname;
    mkdir(tempDir);

    try
        % Download .mhl file
        mhlPath = mip.utils.download_mhl(mhlUrl, tempDir);

        % Create parent directories if needed
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end

        % Extract to package directory
        mip.utils.extract_mhl(mhlPath, pkgDir);

        fprintf('Successfully installed "%s"\n', fqn);

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
