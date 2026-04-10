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
%   mip.install('-e', '.', '--no-compile')          - Editable install, skip compilation
%
% Options:
%   --channel <name>    Install from a specific channel (default: mip-org/core)
%                       Format: 'org/channel' (e.g. 'mip-org/core')
%   --editable, -e      Install in editable mode (local packages only)
%   --no-compile        Skip compilation (editable installs only)
%
% Local packages:
%   To install a local directory, the path must start with '~', '.', '/',
%   or a Windows drive letter (e.g. 'C:\path\mypkg', 'C:/path/mypkg').
%   The directory must contain a mip.yaml file. In editable mode, changes
%   to the source directory are reflected immediately without reinstalling.
%
%   Bare names like 'chebfun' are always resolved against channels, even
%   if a directory of the same name exists in the current folder. Use
%   './chebfun' to force a local install.
%
% Packages can be specified by bare name or fully qualified name
% (org/channel/package). Fully qualified names override the --channel flag.

    if nargin < 1
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Check for --editable / -e and --no-compile flags
    editable = false;
    noCompile = false;
    filteredArgs = {};
    for i = 1:length(varargin)
        arg = varargin{i};
        if ischar(arg) && (strcmp(arg, '--editable') || strcmp(arg, '-e'))
            editable = true;
        elseif ischar(arg) && strcmp(arg, '--no-compile')
            noCompile = true;
        else
            filteredArgs{end+1} = arg;
        end
    end

    if noCompile && ~editable
        error('mip:install:noCompileRequiresEditable', ...
              '--no-compile can only be used with --editable local installs.');
    end

    [channel, args] = mip.utils.parse_channel_flag(filteredArgs);

    if isempty(args)
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Categorize each argument by how it should be installed:
    %   - mhl source   (.mhl file or http(s) URL)
    %   - local path   (starts with ~, ., /, or a Windows drive letter
    %                   like C:\ or C:/)
    %   - repo package (bare name or org/channel/package FQN)
    % Anything else (e.g. 'foo/bar', 'a/b/c/d') is rejected with a hint
    % about prefixing with './' for local installs.
    mhlSources = {};
    localPaths = {};
    repoPackages = {};
    for i = 1:length(args)
        pkg = char(args{i});
        if endsWith(pkg, '.mhl') || startsWith(pkg, 'http://') || startsWith(pkg, 'https://')
            mhlSources{end+1} = pkg; %#ok<*AGROW>
        elseif isLocalPathArg(pkg)
            localPaths{end+1} = pkg;
        else
            parts = strsplit(pkg, '/');
            if length(parts) ~= 1 && length(parts) ~= 3
                error('mip:install:invalidPackageSpec', ...
                      ['Invalid package specifier "%s".\n' ...
                       'Use "package" for a bare name or "org/channel/package" for a fully qualified name.\n' ...
                       'To install a local package, prefix the path with "./":\n' ...
                       '  mip install ./%s'], pkg, pkg);
            end
            repoPackages{end+1} = pkg;
        end
    end

    if editable && isempty(localPaths)
        error('mip:install:editableRequiresLocal', ...
              '--editable can only be used with local directory packages.');
    end

    % Process local directory installs first
    for i = 1:length(localPaths)
        localPath = localPaths{i};
        if ~isfolder(localPath)
            error('mip:install:notADirectory', ...
                  '"%s" is not a directory.', localPath);
        end
        mipYamlPath = fullfile(localPath, 'mip.yaml');
        if ~isfile(mipYamlPath)
            error('mip:install:noMipYaml', ...
                  'Directory "%s" does not contain a mip.yaml file.', localPath);
        end
        mip.utils.install_local(localPath, editable, noCompile);
    end

    % If only local installs were requested, we're done
    if isempty(repoPackages) && isempty(mhlSources)
        return;
    end

    packagesDir = mip.utils.get_packages_dir();

    % Create packages directory if it doesn't exist
    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    % Handle repository packages
    installedFqns = {};

    if ~isempty(repoPackages)
        try
            installedFqns = [installedFqns, installFromRepository(repoPackages, packagesDir, channel)];
        catch ME
            % If a repo install failed and one of the requested names also
            % exists as a relative directory in the current folder, augment
            % the error with a hint about prefixing with './'.
            hint = buildLocalDirHint(repoPackages);
            if ~isempty(hint)
                wrapped = MException(ME.identifier, '%s\n\n%s', ME.message, hint);
                throw(wrapped);
            end
            rethrow(ME);
        end
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
            fprintf('  mip load %s\n', mip.utils.load_hint_name(installedFqns{i}));
        end
    end
end

function installedFqns = installFromRepository(repoPackages, ~, channel)
% Install packages from the mip repository

    installedFqns = {};

    % Determine effective channel for bare-name packages
    if isempty(channel)
        channel = 'mip-org/core';
    end

    [defaultOrg, defaultChan] = mip.utils.parse_channel_spec(channel);

    % Resolve each package argument to org/channel/name (with optional version).
    % FQN arguments use the org/channel encoded in the name; the --channel flag
    % only applies to bare-name arguments. If every argument is a FQN, the
    % --channel value is ignored entirely (no warning, no index fetch).
    % requestedVersions is keyed by FQN so a version constraint reaches the
    % right channel even when the FQN points to a non-primary channel.
    resolvedPackages = {};  % cell array of structs with .org, .channel, .name, .fqn, .requested_version
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    hasBareName = false;
    for i = 1:length(repoPackages)
        pkg = repoPackages{i};
        parsed = mip.utils.parse_package_arg(pkg);
        if ~parsed.is_fqn
            hasBareName = true;
        end
        [org, ch, name, version] = mip.utils.resolve_package_name(pkg, channel);
        fqn = mip.utils.make_fqn(org, ch, name);
        s = struct('org', org, 'channel', ch, 'name', name, ...
                   'fqn', fqn, ...
                   'requested_version', version);
        resolvedPackages{end+1} = s;
        if ~isempty(version)
            requestedVersions(fqn) = version;
        end
    end

    if hasBareName
        fprintf('Using channel: %s/%s\n', defaultOrg, defaultChan);
    end

    % Get current architecture
    currentArch = mip.arch();
    fprintf('Detected architecture: %s\n', currentArch);

    % Build package info map by fetching indexes for all needed channels.
    % Always fetch mip-org/core (bare-name deps resolve there).
    % Fetch the primary channel only if there is at least one bare-name
    % argument (otherwise --channel is being ignored entirely).
    % Also fetch any channels referenced by FQN args.
    packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    unavailablePackages = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fetchedChannels = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    % Collect all channels we need upfront
    channelsToFetch = {'mip-org/core'};
    if hasBareName && ~ismember(channel, channelsToFetch)
        channelsToFetch{end+1} = channel;
    end
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        pkgChannel = [s.org '/' s.channel];
        if ~ismember(pkgChannel, channelsToFetch)
            channelsToFetch{end+1} = pkgChannel;
        end
    end

    % Fetch all needed channel indexes
    for i = 1:length(channelsToFetch)
        ch = channelsToFetch{i};
        fetchChannelIndex(ch, packageInfoMap, unavailablePackages, ...
                          fetchedChannels, requestedVersions);
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

    % Build combined dependency graph.
    % If a cross-channel FQN dep is not in the map, fetch its channel and retry.
    allRequiredFqns = {};
    for attempt = 1:10
        try
            allRequiredFqns = {};
            for i = 1:length(resolvedPackages)
                installOrder = mip.dependency.build_dependency_graph(resolvedPackages{i}.fqn, packageInfoMap);
                allRequiredFqns = [allRequiredFqns, installOrder];
            end
            break  % success
        catch ME
            if ~strcmp(ME.identifier, 'mip:packageNotFound')
                rethrow(ME);
            end
            % Extract missing FQN from error message
            tokens = regexp(ME.message, '"([^"]+)"', 'tokens');
            if isempty(tokens)
                rethrow(ME);
            end
            missingFqn = tokens{1}{1};
            missingResult = mip.utils.parse_package_arg(missingFqn);
            if ~missingResult.is_fqn
                rethrow(ME);
            end
            missingChannel = [missingResult.org '/' missingResult.channel];
            if fetchedChannels.isKey(missingChannel)
                rethrow(ME);  % Already fetched this channel; package truly missing
            end
            % Fetch the missing channel's index
            fprintf('Fetching %s index for cross-channel dependency...\n', missingChannel);
            fetchChannelIndex(missingChannel, packageInfoMap, unavailablePackages, ...
                              fetchedChannels, requestedVersions);
        end
    end
    allRequiredFqns = unique(allRequiredFqns, 'stable');

    % Sort topologically
    allPackagesToInstall = mip.dependency.topological_sort(allRequiredFqns, packageInfoMap);

    % If a user-requested package was given an explicit @version and a
    % different version is currently installed, replace it. Unload first
    % so the install loop below sees a clean slate, and remember to reload
    % afterward. Only trigger when the version that would actually be
    % installed matches the requested version -- otherwise we'd rip out the
    % installed copy only to install the wrong version.
    reloadAfterInstall = {};
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        if isempty(s.requested_version)
            continue;
        end
        pkgDir = mip.utils.get_package_dir(s.org, s.channel, s.name);
        if ~exist(pkgDir, 'dir')
            continue;
        end
        installedInfo = mip.utils.read_package_json(pkgDir);
        if strcmp(installedInfo.version, s.requested_version)
            continue;  % Already at requested version
        end
        if ~packageInfoMap.isKey(s.fqn) || ...
                ~strcmp(packageInfoMap(s.fqn).version, s.requested_version)
            continue;  % Would install a different version; leave alone
        end
        fprintf('Replacing "%s" %s with requested version %s...\n', ...
                s.fqn, installedInfo.version, s.requested_version);
        if mip.utils.is_loaded(s.fqn)
            mip.unload(s.fqn);
            reloadAfterInstall{end+1} = s.fqn;
        end
        rmdir(pkgDir, 's');
        mip.utils.remove_directly_installed(s.fqn);
    end

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

        % Install each package. If any package fails midway, the
        % already-installed-during-this-call dependencies are still on disk
        % but not in directly_installed.txt -- prune them so a failed
        % install doesn't leave orphans behind.
        try
            for i = 1:length(toInstallFqns)
                fqn = toInstallFqns{i};
                pkgInfo = packageInfoMap(fqn);
                result = mip.utils.parse_package_arg(fqn);
                pkgDir = mip.utils.get_package_dir(result.org, result.channel, result.name);
                downloadAndInstall(fqn, pkgInfo, pkgDir);
            end
        catch ME
            fprintf('\nInstall failed; rolling back any orphaned dependencies...\n');
            try
                mip.utils.prune_unused_packages();
            catch pruneErr
                warning('mip:rollbackFailed', ...
                        'Rollback prune failed: %s', pruneErr.message);
            end
            rethrow(ME);
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

    % Reload any packages that were unloaded as part of an @version replacement
    for i = 1:length(reloadAfterInstall)
        fqn = reloadAfterInstall{i};
        fprintf('Reloading "%s"...\n', fqn);
        mip.load(fqn);
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
        channel = 'mip-org/core';
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
        % If installFromRepository succeeded for the dependencies but the
        % .mhl install itself failed (or vice-versa), prune any orphans
        % that were left behind.
        fprintf('\nInstall failed; rolling back any orphaned dependencies...\n');
        try
            mip.utils.prune_unused_packages();
        catch pruneErr
            warning('mip:rollbackFailed', ...
                    'Rollback prune failed: %s', pruneErr.message);
        end
        rethrow(ME);
    end

    % Clean up temp directory
    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
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

function fetchChannelIndex(ch, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions)
% Fetch a channel's index and merge into the package info map.
    if fetchedChannels.isKey(ch)
        return
    end
    fprintf('Fetching package index for %s...\n', ch);
    [chOrg, chName] = mip.utils.parse_channel_spec(ch);
    chIndex = mip.utils.fetch_index(ch);
    % Project the FQN-keyed requestedVersions down to a name-keyed map
    % containing only entries that target this channel. build_package_info_map
    % expects bare-name keys.
    chRequestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fqnKeys = keys(requestedVersions);
    for j = 1:length(fqnKeys)
        parsed = mip.utils.parse_package_arg(fqnKeys{j});
        if strcmp(parsed.org, chOrg) && strcmp(parsed.channel, chName)
            chRequestedVersions(parsed.name) = requestedVersions(fqnKeys{j});
        end
    end
    [chMap, chUnavail] = mip.utils.build_package_info_map(chIndex, chOrg, chName, chRequestedVersions);
    chKeys = keys(chMap);
    for j = 1:length(chKeys)
        packageInfoMap(chKeys{j}) = chMap(chKeys{j});
    end
    chUnavailKeys = keys(chUnavail);
    for j = 1:length(chUnavailKeys)
        unavailablePackages(chUnavailKeys{j}) = chUnavail(chUnavailKeys{j});
    end
    fetchedChannels(ch) = true;
end

function tf = isLocalPathArg(pkg)
% Return true if pkg should be treated as a local directory path.
% Recognizes:
%   - POSIX-style paths starting with '~', '.', or '/'
%   - Windows drive-letter paths like 'C:\foo' or 'C:/foo' (any letter)
    tf = false;
    if isempty(pkg)
        return
    end
    if startsWith(pkg, '~') || startsWith(pkg, '.') || startsWith(pkg, '/')
        tf = true;
        return
    end
    % Windows drive-letter absolute path: <letter>:[\/]...
    if length(pkg) >= 3 && isstrprop(pkg(1), 'alpha') && pkg(2) == ':' ...
            && (pkg(3) == '\' || pkg(3) == '/')
        tf = true;
        return
    end
end

function hint = buildLocalDirHint(repoPackages)
% If any of the repo-style args also exists as a relative directory in
% the current folder, build a hint suggesting the './' form.
    lines = {};
    for i = 1:length(repoPackages)
        pkg = repoPackages{i};
        if isfolder(pkg)
            lines{end+1} = sprintf( ...
                ['Note: a local directory "%s" exists in the current folder.\n' ...
                 'To install it as a local package instead, run:\n' ...
                 '  mip install ./%s'], pkg, pkg);
        end
    end
    hint = strjoin(lines, sprintf('\n\n'));
end
