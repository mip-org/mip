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
%   mip.install('mypkg', '--url', 'https://example.com/pkg.zip')
%                                                    - Install from a remote .zip URL
%
% Options:
%   --channel <name>    Install from a specific channel (default: mip-org/core)
%                       Format: 'org/channel' (e.g. 'mip-org/core')
%   --editable, -e      Install in editable mode (local packages only)
%   --no-compile        Skip compilation (editable installs only)
%   --url <zip-url>     Install from a remote .zip archive. The positional
%                       argument is used as the package name. At most one
%                       --url per call; incompatible with --editable.
%                       File Exchange landing URLs (https://www.mathworks
%                       .com/matlabcentral/fileexchange/...) are also
%                       accepted and auto-resolved to their .zip download.
%
% Local packages:
%   To install a local directory, the path must start with '~', '.', '/',
%   or a Windows drive letter (e.g. 'C:\path\mypkg', 'C:/path/mypkg').
%   The directory must contain a mip.yaml file. In editable mode, changes
%   to the source directory are reflected immediately without reinstalling.
%   '@' in local paths is treated as a literal character, not a version
%   separator (e.g. './@MyClass', './pkg@dev' are valid local paths).
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

    % Check for --editable / -e, --no-compile, and --url flags
    editable = false;
    noCompile = false;
    zipUrl = '';
    urlSeen = false;
    filteredArgs = {};
    i = 1;
    while i <= length(varargin)
        arg = varargin{i};
        if ischar(arg) && (strcmp(arg, '--editable') || strcmp(arg, '-e'))
            editable = true;
            i = i + 1;
        elseif ischar(arg) && strcmp(arg, '--no-compile')
            noCompile = true;
            i = i + 1;
        elseif ischar(arg) && strcmp(arg, '--url')
            if urlSeen
                error('mip:install:multipleUrls', ...
                      '--url may be specified at most once per install call.');
            end
            if i + 1 > length(varargin)
                error('mip:install:missingUrlValue', '--url requires a value.');
            end
            zipUrl = varargin{i + 1};
            urlSeen = true;
            i = i + 2;
        else
            filteredArgs{end+1} = arg; %#ok<AGROW>
            i = i + 1;
        end
    end

    if noCompile && ~editable
        error('mip:install:noCompileRequiresEditable', ...
              '--no-compile can only be used with --editable local installs.');
    end

    [channel, args] = mip.parse.parse_channel_flag(filteredArgs);

    if urlSeen
        installFromUrlFlag(args, zipUrl, editable, noCompile);
        return;
    end

    if isempty(args)
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Categorize each argument by how it should be installed:
    %   - mhl source   (.mhl file or http(s) URL)
    %   - local path   (starts with ~, ., /, or a Windows drive letter)
    %   - repo package (bare name or org/channel/package FQN)
    mhlSources = {};
    localPaths = {};
    repoPackages = {};
    for i = 1:length(args)
        pkg = char(args{i});
        if endsWith(pkg, '.mhl') || startsWith(pkg, 'http://') || startsWith(pkg, 'https://')
            mhlSources{end+1} = pkg; %#ok<AGROW>
        elseif isLocalPathArg(pkg)
            localPaths{end+1} = pkg; %#ok<AGROW>
        else
            parts = strsplit(pkg, '/');
            if length(parts) ~= 1 && length(parts) ~= 3
                error('mip:install:invalidPackageSpec', ...
                      ['Invalid package specifier "%s".\n' ...
                       'Use "package" for a bare name or "org/channel/package" for a fully qualified name.\n' ...
                       'To install a local package, prefix the path with "./":\n' ...
                       '  mip install ./%s'], pkg, pkg);
            end
            repoPackages{end+1} = pkg; %#ok<AGROW>
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
        if ~isfile(fullfile(localPath, 'mip.yaml'))
            if confirmAutoInit(localPath)
                mip.init(localPath);
                fprintf('\n');
            else
                error('mip:install:abortedNoMipYaml', ...
                      ['Directory "%s" does not contain a mip.yaml file ' ...
                       'and the user declined to auto-generate one. ' ...
                       'Install aborted.'], localPath);
            end
        end
        mip.build.install_local(localPath, editable, noCompile);
    end

    % If only local installs were requested, we're done
    if isempty(repoPackages) && isempty(mhlSources)
        return;
    end

    packagesDir = mip.paths.get_packages_dir();
    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    % Handle repository packages
    installedFqns = {};

    if ~isempty(repoPackages)
        try
            installedFqns = [installedFqns, installFromRepository(repoPackages, channel)];
        catch ME
            hint = buildLocalDirHint(repoPackages);
            if ~isempty(hint)
                throw(MException(ME.identifier, '%s\n\n%s', ME.message, hint));
            end
            rethrow(ME);
        end
    end

    % Handle .mhl file installations
    for i = 1:length(mhlSources)
        fqn = installFromMhl(mhlSources{i}, packagesDir, channel);
        if ~isempty(fqn)
            installedFqns = [installedFqns, {fqn}]; %#ok<AGROW>
        end
    end

    % Summary
    if isempty(installedFqns) && isempty(mhlSources)
        fprintf('\nAll packages already installed.\n');
    elseif ~isempty(installedFqns)
        fprintf('\nSuccessfully installed %d package(s).\n', length(installedFqns));
        fprintf('\nTo use installed packages, run:\n');
        for i = 1:length(installedFqns)
            fprintf('  mip load %s\n', mip.resolve.get_shortest_name(installedFqns{i}));
        end
    end
end

function installedFqns = installFromRepository(repoPackages, channel)
% Install packages from the mip repository.

    installedFqns = {};

    % Determine effective channel for bare-name packages
    if isempty(channel)
        channel = 'mip-org/core';
    end
    [defaultOrg, defaultChan] = mip.parse.parse_channel_spec(channel);

    % Resolve each package argument to org/channel/name (with optional version).
    resolvedPackages = {};
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    hasBareName = false;
    for i = 1:length(repoPackages)
        parsed = mip.parse.parse_package_arg(repoPackages{i});
        if ~parsed.is_fqn
            hasBareName = true;
        end
        [org, ch, name, version] = mip.resolve.resolve_package_name(repoPackages{i}, channel);
        fqn = mip.parse.make_fqn(org, ch, name);
        resolvedPackages{end+1} = struct('org', org, 'channel', ch, 'name', name, ... %#ok<AGROW>
                                         'fqn', fqn, 'requested_version', version);
        if ~isempty(version)
            requestedVersions(fqn) = version;
        end
    end

    if hasBareName
        fprintf('Using channel: %s/%s\n', defaultOrg, defaultChan);
    end

    currentArch = mip.arch();
    fprintf('Detected architecture: %s\n', currentArch);

    % Fetch channel indexes. Always fetch mip-org/core (bare-name deps resolve
    % there). Fetch the --channel value only when there is at least one bare-name
    % argument. Also fetch channels referenced by FQN args. fetchChannelIndex
    % skips channels that have already been fetched.
    packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    unavailablePackages = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fetchedChannels = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    fetchChannelIndex('mip-org/core', packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
    if hasBareName
        fetchChannelIndex(channel, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
    end
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        fetchChannelIndex([s.org '/' s.channel], packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
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
        allRequiredFqns = {};
        allMissing = {};
        for i = 1:length(resolvedPackages)
            [installOrder, missing] = mip.dependency.build_dependency_graph(resolvedPackages{i}.fqn, packageInfoMap);
            allRequiredFqns = [allRequiredFqns, installOrder]; %#ok<AGROW>
            allMissing = [allMissing, missing]; %#ok<AGROW>
        end
        allMissing = unique(allMissing, 'stable');

        if isempty(allMissing)
            break
        end

        % Fetch channels for missing cross-channel dependencies
        fetchedNew = false;
        for i = 1:length(allMissing)
            parsed = mip.parse.parse_package_arg(allMissing{i});
            if ~parsed.is_fqn
                error('mip:packageNotFound', 'Package "%s" not found in repository', allMissing{i});
            end
            missingChannel = [parsed.org '/' parsed.channel];
            if fetchedChannels.isKey(missingChannel)
                continue
            end
            fprintf('Fetching %s index for cross-channel dependency...\n', missingChannel);
            fetchChannelIndex(missingChannel, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
            fetchedNew = true;
        end

        if ~fetchedNew
            % All channels already fetched but packages still missing
            error('mip:packageNotFound', ...
                  'Package(s) not found in repository: %s', strjoin(allMissing, ', '));
        end
    end
    allRequiredFqns = unique(allRequiredFqns, 'stable');

    % Sort topologically
    allPackagesToInstall = mip.dependency.topological_sort(allRequiredFqns, packageInfoMap);

    % If a user-requested @version differs from what's installed, replace it
    reloadAfterInstall = replaceExistingVersions(resolvedPackages, packageInfoMap);

    % Determine which packages need installing vs already installed
    toInstallFqns = {};
    for i = 1:length(allPackagesToInstall)
        fqn = allPackagesToInstall{i};
        result = mip.parse.parse_package_arg(fqn);
        pkgDir = mip.paths.get_package_dir(result.org, result.channel, result.name);
        if exist(pkgDir, 'dir')
            fprintf('Package "%s" is already installed\n', fqn);
        else
            toInstallFqns{end+1} = fqn; %#ok<AGROW>
        end
    end

    % Show installation plan and install
    if ~isempty(toInstallFqns)
        if length(toInstallFqns) == 1
            fprintf('\nInstallation plan:\n');
        else
            fprintf('\nInstallation plan (%d packages):\n', length(toInstallFqns));
        end
        for i = 1:length(toInstallFqns)
            fprintf('  - %s %s\n', toInstallFqns{i}, packageInfoMap(toInstallFqns{i}).version);
        end
        fprintf('\n');

        % Install each package. On failure, prune orphaned deps that were
        % installed during this call (they aren't in directly_installed.txt yet).
        try
            for i = 1:length(toInstallFqns)
                fqn = toInstallFqns{i};
                result = mip.parse.parse_package_arg(fqn);
                pkgDir = mip.paths.get_package_dir(result.org, result.channel, result.name);
                downloadAndInstall(fqn, packageInfoMap(fqn), pkgDir);
            end
        catch ME
            fprintf('\nInstall failed; rolling back any orphaned dependencies...\n');
            try
                mip.state.prune_unused_packages();
            catch pruneErr
                warning('mip:rollbackFailed', ...
                        'Rollback prune failed: %s', pruneErr.message);
            end
            rethrow(ME);
        end

        % Mark requested packages as directly installed and collect their FQNs
        for i = 1:length(resolvedPackages)
            s = resolvedPackages{i};
            mip.state.add_directly_installed(s.fqn);
            if ismember(s.fqn, toInstallFqns)
                installedFqns{end+1} = s.fqn; %#ok<AGROW>
            end
        end
    end

    % Reload any packages that were unloaded as part of an @version replacement
    for i = 1:length(reloadAfterInstall)
        fprintf('Reloading "%s"...\n', reloadAfterInstall{i});
        mip.load(reloadAfterInstall{i});
    end

    % Warn if any installed package name exists in multiple channels
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        allInstalled = mip.resolve.find_all_installed_by_name(s.name);
        if length(allInstalled) > 1
            fprintf('\nWarning: Package "%s" is installed from multiple channels:\n', s.name);
            for k = 1:length(allInstalled)
                fprintf('  - %s\n', allInstalled{k});
            end
        end
    end
end

function reloadAfterInstall = replaceExistingVersions(resolvedPackages, packageInfoMap)
% Replace installed packages when the user requested a different @version.
% Returns FQNs that were loaded before replacement (caller should reload them).
    reloadAfterInstall = {};
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        if isempty(s.requested_version)
            continue;
        end
        pkgDir = mip.paths.get_package_dir(s.org, s.channel, s.name);
        if ~exist(pkgDir, 'dir')
            continue;
        end
        installedInfo = mip.config.read_package_json(pkgDir);
        if strcmp(installedInfo.version, s.requested_version)
            continue;
        end
        if ~packageInfoMap.isKey(s.fqn) || ...
                ~strcmp(packageInfoMap(s.fqn).version, s.requested_version)
            continue;
        end
        fprintf('Replacing "%s" %s with requested version %s...\n', ...
                s.fqn, installedInfo.version, s.requested_version);
        if mip.state.is_loaded(s.fqn)
            mip.unload(s.fqn);
            reloadAfterInstall{end+1} = s.fqn; %#ok<AGROW>
        end
        rmdir(pkgDir, 's');
        mip.state.remove_directly_installed(s.fqn);
    end
end

function installedFqn = installFromMhl(mhlSource, ~, channel)
% Install a package from a local .mhl file or URL.

    installedFqn = '';
    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    if isempty(channel)
        channel = 'mip-org/core';
    end
    [org, channelName] = mip.parse.parse_channel_spec(channel);

    try
        mhlPath = mip.channel.download_mhl(mhlSource, tempDir);
        extractDir = fullfile(tempDir, 'extracted');
        mip.channel.extract_mhl(mhlPath, extractDir);

        pkgInfo = mip.config.read_package_json(extractDir);
        packageName = pkgInfo.name;
        fqn = mip.parse.make_fqn(org, channelName, packageName);

        pkgDir = mip.paths.get_package_dir(org, channelName, packageName);
        if exist(pkgDir, 'dir')
            fprintf('Package "%s" is already installed\n', fqn);
            return
        end

        if ~isempty(pkgInfo.dependencies)
            fprintf('\nPackage "%s" has dependencies: %s\n', ...
                    fqn, strjoin(pkgInfo.dependencies, ', '));
            fprintf('Installing dependencies from remote repository...\n');
            installFromRepository(pkgInfo.dependencies, channel);
        end

        fprintf('\nInstalling "%s"...\n', fqn);
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end
        movefile(extractDir, pkgDir);
        fprintf('Successfully installed "%s"\n', fqn);
        mip.state.add_directly_installed(fqn);
        installedFqn = fqn;

    catch ME
        fprintf('\nInstall failed; rolling back any orphaned dependencies...\n');
        try
            mip.state.prune_unused_packages();
        catch pruneErr
            warning('mip:rollbackFailed', ...
                    'Rollback prune failed: %s', pruneErr.message);
        end
        rethrow(ME);
    end
end

function downloadAndInstall(fqn, packageInfo, pkgDir)
% Download and install a single package.

    fprintf('Downloading %s %s...\n', fqn, packageInfo.version);

    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    try
        mhlPath = mip.channel.download_mhl(packageInfo.mhl_url, tempDir);
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end
        mip.channel.extract_mhl(mhlPath, pkgDir);
        fprintf('Successfully installed "%s"\n', fqn);
    catch ME
        if exist(pkgDir, 'dir')
            rmdir(pkgDir, 's');
        end
        rethrow(ME);
    end
end

function fetchChannelIndex(ch, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions)
% Fetch a channel's index and merge into the package info map.
    if fetchedChannels.isKey(ch)
        return
    end
    fprintf('Fetching package index for %s...\n', ch);
    [chOrg, chName] = mip.parse.parse_channel_spec(ch);
    chIndex = mip.channel.fetch_index(ch);
    % Project FQN-keyed requestedVersions down to name-keyed map for this channel
    chRequestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fqnKeys = keys(requestedVersions);
    for j = 1:length(fqnKeys)
        parsed = mip.parse.parse_package_arg(fqnKeys{j});
        if strcmp(parsed.org, chOrg) && strcmp(parsed.channel, chName)
            chRequestedVersions(parsed.name) = requestedVersions(fqnKeys{j});
        end
    end
    [chMap, chUnavail] = mip.resolve.build_package_info_map(chIndex, chOrg, chName, chRequestedVersions);
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

function rmTempDir(d)
    if exist(d, 'dir')
        rmdir(d, 's');
    end
end

function tf = confirmAutoInit(localPath)
% Ask the user whether to auto-generate a mip.yaml in localPath.
% Honors MIP_CONFIRM as a non-interactive override (matching uninstall.m).
% Returns true on "y"/"yes", false otherwise.
    fprintf('\nDirectory "%s" does not contain a mip.yaml file.\n', localPath);
    fprintf('mip can auto-generate one for you (equivalent to running `mip init`).\n');
    confirm = getenv('MIP_CONFIRM');
    if isempty(confirm)
        confirm = input('Auto-generate mip.yaml? (y/n): ', 's');
    end
    tf = strcmpi(confirm, 'y') || strcmpi(confirm, 'yes');
end

function installFromUrlFlag(args, zipUrl, editable, noCompile)
% Handle `mip install <name> --url <zipUrl>`.
%
% Validation: exactly one positional arg, which must be a bare name
% (not an FQN, not a path, not itself a URL). The URL must point at
% a .zip (path component, ignoring query/fragment, ends in .zip).
% --editable is rejected since the source directory is temporary.
%
% Then: download the zip, extract, unwrap a single top-level subdir
% if present, auto-generate a mip.yaml if missing (with the URL in
% the repository field), and run a non-editable local install.

    if editable
        error('mip:install:editableRequiresLocal', ...
              '--editable cannot be used with --url installs.');
    end

    if isempty(args)
        error('mip:install:urlRequiresName', ...
              ['--url requires a positional package name.\n' ...
               'Example: mip install mypkg --url %s'], zipUrl);
    end
    if length(args) > 1
        error('mip:install:urlTakesSingleName', ...
              '--url takes exactly one positional package name; got %d.', ...
              length(args));
    end

    pkgName = char(args{1});
    if startsWith(pkgName, 'http://') || startsWith(pkgName, 'https://') || ...
       endsWith(pkgName, '.mhl') || isLocalPathArg(pkgName) || ...
       contains(pkgName, '/')
        error('mip:install:urlTakesSingleName', ...
              ['With --url, the positional argument must be a bare package ' ...
               'name (not a URL, path, or FQN). Got: %s'], pkgName);
    end

    parsed = mip.parse.parse_package_arg(pkgName);  % validates name chars
    pkgName = parsed.name;

    % If the URL is a File Exchange landing page, resolve it to the
    % underlying .zip download URL. The resolved URL (with query string
    % stripped) is what gets baked into the generated mip.yaml.
    if isFileExchangeUrl(zipUrl)
        fprintf('Resolving File Exchange URL %s...\n', zipUrl);
        zipUrl = resolveFileExchangeUrl(zipUrl);
        fprintf('Resolved to %s\n', zipUrl);
    end

    if ~isZipUrl(zipUrl)
        error('mip:install:urlMustBeZip', ...
              ['--url value must point to a .zip archive or a File Exchange ' ...
               'page. Got: %s'], zipUrl);
    end

    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    fprintf('Downloading %s...\n', zipUrl);
    zipPath = fullfile(tempDir, 'package.zip');
    try
        websave(zipPath, zipUrl, weboptions('Timeout', 300));
    catch ME
        error('mip:install:zipDownloadFailed', ...
              'Failed to download %s: %s', zipUrl, ME.message);
    end

    extractRoot = fullfile(tempDir, 'extracted');
    mkdir(extractRoot);
    fprintf('Extracting...\n');
    try
        unzip(zipPath, extractRoot);
    catch ME
        error('mip:install:zipExtractFailed', ...
              'Failed to extract %s: %s', zipUrl, ME.message);
    end

    % If the zip extracted to a single top-level directory (e.g. GitHub
    % archive zips produce a `<repo>-<branch>/` wrapper), descend into
    % it. Otherwise use the extraction root directly.
    sourceDir = unwrapSingleSubdir(extractRoot);

    if ~isfile(fullfile(sourceDir, 'mip.yaml'))
        fprintf('No mip.yaml found in archive; auto-generating...\n');
        mip.init(sourceDir, '--name', pkgName, '--repository', zipUrl);
        fprintf('\n');
    end

    mip.build.install_local(sourceDir, false, noCompile);

    % Clear source_path in the installed mip.json. `install_local` records
    % the extracted source dir, but that temp dir is deleted when this
    % function returns, so the stored path would be stale. An empty
    % source_path signals "no source available to reinstall from";
    % `mip update` skips such packages.
    clearSourcePath(pkgName);
end

function clearSourcePath(pkgName)
    mipJsonPath = fullfile(mip.paths.get_package_dir('local', 'local', pkgName), 'mip.json');
    if ~isfile(mipJsonPath)
        return
    end
    mipData = jsondecode(fileread(mipJsonPath));
    mipData.source_path = '';
    fid = fopen(mipJsonPath, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to mip.json at %s', mipJsonPath);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, jsonencode(mipData));
end

function tf = isFileExchangeUrl(url)
% A MathWorks File Exchange landing page looks like
%   https://www.mathworks.com/matlabcentral/fileexchange/<id>[-<slug>]
% (with optional query string).
    if ~ischar(url) && ~isstring(url)
        tf = false; return;
    end
    url = char(url);
    tf = startsWith(url, 'https://www.mathworks.com/matlabcentral/fileexchange/') || ...
         startsWith(url, 'http://www.mathworks.com/matlabcentral/fileexchange/');
end

function zipUrl = resolveFileExchangeUrl(fxUrl)
% Resolve a File Exchange landing URL to the underlying .zip download URL.
% Appends ?download=true (or &download=true if a query string is already
% present), issues a HEAD request, follows the 302 redirect to the UUID-
% based mlc-downloads URL, and strips the resulting URL's query string.
%
% A non-default User-Agent is required: the MathWorks Akamai layer
% returns 403 to MATLAB's default UA, but accepts curl-style UAs.

    if contains(fxUrl, '?')
        landingUrl = [fxUrl '&download=true'];
    else
        landingUrl = [fxUrl '?download=true'];
    end

    try
        uri = matlab.net.URI(landingUrl);
        req = matlab.net.http.RequestMessage('HEAD');
        req.Header = matlab.net.http.HeaderField('User-Agent', 'curl/8.0');
        opt = matlab.net.http.HTTPOptions('ConnectTimeout', 30);
        [~, ~, history] = send(req, uri, opt);
    catch ME
        error('mip:install:fxResolveFailed', ...
              'Failed to resolve File Exchange URL %s: %s', fxUrl, ME.message);
    end

    if isempty(history)
        error('mip:install:fxResolveFailed', ...
              'Empty redirect history for File Exchange URL %s.', fxUrl);
    end

    finalStatus = double(history(end).Response.StatusCode);
    if finalStatus < 200 || finalStatus >= 300
        error('mip:install:fxResolveFailed', ...
              'File Exchange URL %s returned HTTP %d.', fxUrl, finalStatus);
    end

    finalUrl = char(history(end).URI);

    % Strip query string and fragment.
    qIdx = strfind(finalUrl, '?');
    if ~isempty(qIdx)
        finalUrl = finalUrl(1:qIdx(1)-1);
    end
    hIdx = strfind(finalUrl, '#');
    if ~isempty(hIdx)
        finalUrl = finalUrl(1:hIdx(1)-1);
    end

    if ~endsWith(lower(finalUrl), '.zip')
        error('mip:install:fxResolveFailed', ...
              ['File Exchange URL %s did not resolve to a .zip URL ' ...
               '(got: %s).'], fxUrl, finalUrl);
    end

    zipUrl = finalUrl;
end

function tf = isZipUrl(url)
% Return true if url is an http(s) URL whose path component ends in .zip
% (case-insensitive). The path component is everything before the first
% '?' (query) or '#' (fragment).
    if ~ischar(url) && ~isstring(url)
        tf = false; return;
    end
    url = char(url);
    if ~startsWith(url, 'http://') && ~startsWith(url, 'https://')
        tf = false;
        return
    end
    pathPart = url;
    qIdx = strfind(pathPart, '?');
    if ~isempty(qIdx)
        pathPart = pathPart(1:qIdx(1)-1);
    end
    hIdx = strfind(pathPart, '#');
    if ~isempty(hIdx)
        pathPart = pathPart(1:hIdx(1)-1);
    end
    tf = endsWith(lower(pathPart), '.zip');
end

function dir2 = unwrapSingleSubdir(d)
% If d contains exactly one entry and it is a directory, return that
% subdirectory. Otherwise return d unchanged.
    entries = dir(d);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    if isscalar(entries) && entries(1).isdir
        dir2 = fullfile(d, entries(1).name);
    else
        dir2 = d;
    end
end

function tf = isLocalPathArg(pkg)
% Return true if pkg should be treated as a local directory path.
    if isempty(pkg)
        tf = false;
        return
    end
    tf = startsWith(pkg, '~') || startsWith(pkg, '.') || startsWith(pkg, '/') || ...
         (length(pkg) >= 3 && isstrprop(pkg(1), 'alpha') && pkg(2) == ':' && ...
          (pkg(3) == '\' || pkg(3) == '/'));
end

function hint = buildLocalDirHint(repoPackages)
% If any of the repo-style args also exists as a relative directory in
% the current folder, build a hint suggesting the './' form.
% Also checks the base name after stripping any @version suffix, since
% local paths treat '@' as a literal character (not a version separator).
    lines = {};
    for i = 1:length(repoPackages)
        dirName = matchLocalDir(repoPackages{i});
        if ~isempty(dirName)
            lines{end+1} = sprintf( ... %#ok<AGROW>
                ['Note: a local directory "%s" exists in the current folder.\n' ...
                 'To install it as a local package instead, run:\n' ...
                 '  mip install ./%s'], dirName, dirName);
        end
    end
    hint = strjoin(lines, sprintf('\n\n'));
end

function dirName = matchLocalDir(pkg)
% Check if pkg matches a local directory, either as-is or after stripping
% a trailing @version suffix.
    dirName = '';
    if isfolder(pkg)
        dirName = pkg;
    else
        atIdx = strfind(pkg, '@');
        if ~isempty(atIdx)
            baseName = pkg(1:atIdx(end)-1);
            if isfolder(baseName)
                dirName = baseName;
            end
        end
    end
end
