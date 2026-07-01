function installedFqns = from_repository(repoPackages, channel, markDirectlyInstalled)
%FROM_REPOSITORY   Install packages from channel repositories.
%
% The channel-install pipeline, in three phases:
%   1. resolveRequests - resolve each argument to a channel-canonical FQN
%      against the fetched channel indexes.
%   2. planInstall     - build the combined dependency graph (fetching
%      cross-channel indexes on demand) and topologically sort it.
%   3. executeInstall  - replace @version-pinned installs, download and
%      install the plan, roll back on failure, and update state.
%
% markDirectlyInstalled (default true) controls whether the packages in
% repoPackages are added to directly_installed.txt. Callers installing
% transitive dependencies (e.g. .mhl installs pulling their own deps)
% should pass false so those deps can be pruned when their parent is
% uninstalled.
%
% Args:
%   repoPackages          - Cell array of package args (bare names or FQNs,
%                           optionally with @version suffixes)
%   channel               - Channel spec from --channel, or '' for the
%                           priority list (mip-org/core, then subscriptions)
%   markDirectlyInstalled - (Optional) See above. Default true.
%
% Returns:
%   installedFqns - Cell array of FQNs newly installed by this call.

    if nargin < 3
        markDirectlyInstalled = true;
    end

    installedFqns = {};

    [resolvedPackages, packageInfoMap, unavailablePackages, ...
        fetchedChannels, requestedVersions] = resolveRequests(repoPackages, channel);

    % mip cannot switch its own version through the normal unload/replace
    % path below: it is the code currently executing, so unloading it
    % (mip.unload rejects the self identity outright) or moving its directory
    % would break the running session. When a *different* version of mip is
    % requested, hot-swap it in place instead, then drop it from the list so
    % the remaining packages install normally. Same-version or versionless
    % requests fall through untouched — the generic path below correctly
    % reports "already installed" without attempting to unload mip.
    keepPackage = true(1, length(resolvedPackages));
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        if ~strcmp(s.fqn, 'gh/mip-org/core/mip') || isempty(s.requested_version)
            continue
        end
        selfPkgDir = mip.paths.get_package_dir(s.fqn);
        installedInfo = mip.config.read_package_json(selfPkgDir);
        latestInfo = packageInfoMap(s.fqn);
        if strcmp(installedInfo.version, latestInfo.version)
            continue
        end
        fprintf('Replacing "%s" %s with requested version %s...\n', ...
                mip.parse.display_fqn(s.fqn), installedInfo.version, s.requested_version);
        mip.self.hot_swap(selfPkgDir, installedInfo, latestInfo);
        fprintf('Successfully installed "%s"\n', mip.parse.display_fqn(s.fqn));
        installedFqns{end+1} = s.fqn; %#ok<AGROW>
        keepPackage(i) = false;
    end
    resolvedPackages = resolvedPackages(keepPackage);
    if isempty(resolvedPackages)
        return
    end

    allPackagesToInstall = planInstall(resolvedPackages, packageInfoMap, ...
        unavailablePackages, fetchedChannels, requestedVersions);

    installedFqns = [installedFqns, executeInstall(resolvedPackages, ...
        allPackagesToInstall, packageInfoMap, markDirectlyInstalled)];
end

function [resolvedPackages, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions] = resolveRequests(repoPackages, channel)
% Resolve each package argument to a channel-canonical FQN, fetching the
% channel indexes needed along the way. Errors if a requested package is
% missing from its channel or unavailable for this architecture.

    % Capture whether the user explicitly passed --channel: if not, bare-name
    % args are resolved against the priority list (core, then subscribed
    % channels). If yes, --channel is the only place to look for them.
    userPassedChannel = ~isempty(channel);
    if isempty(channel)
        channel = 'mip-org/core';
    end
    [defaultOwner, defaultChan] = mip.parse.parse_channel_spec(channel);

    % Pre-parse args so we can distinguish FQN args from bare-name args
    % before assigning channels to the latter.
    parsedArgs = cell(1, length(repoPackages));
    hasBareName = false;
    for i = 1:length(repoPackages)
        parsedArgs{i} = mip.parse.parse_package_arg(repoPackages{i});
        if ~parsedArgs{i}.is_fqn
            hasBareName = true;
        end
    end

    % Determine effective channel for each bare-name arg.
    %   userPassedChannel: bare names go to that channel (existing behavior).
    %   else: walk the priority list (core, then `mip channel add` order)
    %         and pick the first channel that publishes the bare name.
    %   unresolvedBareIdx tracks bare names not found in any priority channel,
    %   so the downstream "not found" error can list the channels consulted.
    bareChannels = cell(1, length(repoPackages));
    unresolvedBareIdx = false(1, length(repoPackages));
    priorityChannels = {};
    skippedChannels = {};
    if hasBareName && ~userPassedChannel
        priorityChannels = [{'mip-org/core'}, mip.state.get_channels()];
        [bareChannels, skippedChannels] = resolveBareNameChannels(parsedArgs, priorityChannels);
        for j = 1:length(parsedArgs)
            if ~parsedArgs{j}.is_fqn && isempty(bareChannels{j})
                bareChannels{j} = 'mip-org/core';
                unresolvedBareIdx(j) = true;
            end
        end
    end

    % Resolve each package argument to <owner>/<channel>/<name> (with optional version).
    resolvedPackages = {};
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:length(repoPackages)
        parsed = parsedArgs{i};
        if parsed.is_fqn
            effChannel = '';  % FQN provides its own channel
        elseif userPassedChannel
            effChannel = channel;
        else
            effChannel = bareChannels{i};
        end
        [owner, ch, name, version] = mip.resolve.resolve_package_name(repoPackages{i}, effChannel);
        fqn = mip.parse.make_fqn(owner, ch, name);
        resolvedPackages{end+1} = struct('owner', owner, 'channel', ch, 'name', name, ... %#ok<AGROW>
                                         'fqn', fqn, 'requested_version', version);
        if ~isempty(version)
            requestedVersions(fqn) = version;
        end
    end

    if hasBareName
        if userPassedChannel || isempty(priorityChannels) || isscalar(priorityChannels)
            fprintf('Using channel: %s/%s\n', defaultOwner, defaultChan);
        else
            fprintf('Using channels (priority order): %s\n', strjoin(priorityChannels, ', '));
        end
    end

    currentArch = mip.build.arch();
    fprintf('Detected architecture: %s\n', currentArch);

    % Fetch channel indexes. Always fetch mip-org/core (bare-name deps resolve
    % there). When --channel was given and there is at least one bare-name
    % argument, fetch that channel too. Channels referenced by resolved
    % packages (FQN args plus subscription-resolved bare names) are fetched
    % via the loop. fetchChannelIndex skips channels that have already been
    % fetched.
    packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    unavailablePackages = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fetchedChannels = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    fetchChannelIndex('mip-org/core', packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
    if hasBareName && userPassedChannel
        fetchChannelIndex(channel, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
    end
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        fetchChannelIndex([s.owner '/' s.channel], packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
    end

    % Canonicalize each requested package to the channel-published name.
    % The user may have typed a name that differs in case or in `-`/`_`
    % from the channel's form; from here on we use the channel-canonical
    % form so the install path on disk and stored FQN match what other
    % commands will look up.
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        canonical = mip.resolve.canonicalize_in_map(s.fqn, packageInfoMap);
        if ~strcmp(canonical, s.fqn)
            cParsed = mip.parse.parse_package_arg(canonical);
            s.name = cParsed.name;
            s.fqn = canonical;
            resolvedPackages{i} = s;
        end
    end

    % Check if any requested packages are unavailable
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        if ~packageInfoMap.isKey(s.fqn)
            if unavailablePackages.isKey(s.fqn)
                archs = unavailablePackages(s.fqn);
                fprintf('\nError: Package "%s" is not available for architecture "%s"\n', ...
                        mip.parse.display_fqn(s.fqn), currentArch);
                fprintf('Available architectures: %s\n', strjoin(archs, ', '));
                error('mip:packageUnavailable', 'Package not available for this architecture');
            elseif unresolvedBareIdx(i)
                if isempty(skippedChannels)
                    error('mip:packageNotFound', ...
                          'Package "%s" not found in any of: %s', ...
                          parsedArgs{i}.name, strjoin(priorityChannels, ', '));
                else
                    error('mip:packageNotFound', ...
                          ['Package "%s" not found in any of: %s\n' ...
                           '  (could not fetch indexes for: %s)'], ...
                          parsedArgs{i}.name, ...
                          strjoin(priorityChannels, ', '), ...
                          strjoin(skippedChannels, ', '));
                end
            else
                error('mip:packageNotFound', ...
                      'Package "%s" not found in repository', mip.parse.display_fqn(s.fqn));
            end
        end
    end
end

function allPackagesToInstall = planInstall(resolvedPackages, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions)
% Build the combined dependency graph for the resolved packages and sort
% it topologically. Cross-channel FQN dependencies whose channels have
% not been fetched yet are fetched on demand (mutating the shared maps
% in place) and the graph build is retried.

    if length(resolvedPackages) == 1
        fprintf('Resolving dependencies for "%s"...\n', mip.parse.display_fqn(resolvedPackages{1}.fqn));
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
            if ~parsed.is_fqn || ~strcmp(parsed.type, 'gh')
                error('mip:packageNotFound', 'Package "%s" not found in repository', mip.parse.display_fqn(allMissing{i}));
            end
            missingChannel = [parsed.owner '/' parsed.channel];
            if fetchedChannels.isKey(missingChannel)
                continue
            end
            fprintf('Fetching %s index for cross-channel dependency...\n', missingChannel);
            fetchChannelIndex(missingChannel, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions);
            fetchedNew = true;
        end

        if ~fetchedNew
            % All channels already fetched but packages still missing
            missingDisplay = cellfun(@mip.parse.display_fqn, allMissing, 'UniformOutput', false);
            error('mip:packageNotFound', ...
                  'Package(s) not found in repository: %s', strjoin(missingDisplay, ', '));
        end
    end
    allRequiredFqns = unique(allRequiredFqns, 'stable');

    % Sort topologically. build_dependency_graph already returns each
    % root's list dependencies-first, so allRequiredFqns is already in
    % topological order; this re-sort is defensive.
    allPackagesToInstall = mip.dependency.topological_sort(allRequiredFqns, packageInfoMap);
end

function installedFqns = executeInstall(resolvedPackages, allPackagesToInstall, packageInfoMap, markDirectlyInstalled)
% Carry out the install plan: replace @version-pinned installs, download
% and install everything not already present, roll back on failure, and
% update install state.

    installedFqns = {};

    % If a user-requested @version differs from what's installed, replace it.
    % Old versions are staged to backup dirs; restored on failure below.
    [reloadAfterInstall, replacementBackups] = replaceExistingVersions(resolvedPackages, packageInfoMap);

    % From here on, any error must restore @version backups. If a download
    % was actually attempted, also prune orphan deps installed during this
    % call (they aren't in directly_installed.txt yet). Restore happens
    % before prune so prune doesn't drop deps of the restored packages.
    installAttempted = false;
    try
        % Determine which packages need installing vs already installed.
        % Reject equivalent-but-different on-disk names (e.g. user asks for
        % "some-packagE" while "some_package" is already installed): their
        % FQNs share a normalized form, so letting both coexist would give
        % two parallel installs for one logical package.
        toInstallFqns = {};
        for i = 1:length(allPackagesToInstall)
            fqn = allPackagesToInstall{i};
            result = mip.parse.parse_package_arg(fqn);
            existingName = mip.resolve.installed_dir(fqn);
            if ~isempty(existingName) && ~strcmp(existingName, result.name)
                existingFqn = mip.parse.make_fqn(result.owner, result.channel, existingName);
                error('mip:install:equivalentAlreadyInstalled', ...
                      ['Cannot install "%s": an equivalent package "%s" is already installed. ' ...
                       'Package names are equivalent when they match after lowercasing and ' ...
                       'treating "-" and "_" as the same character. Uninstall "%s" first.'], ...
                      mip.parse.display_fqn(fqn), mip.parse.display_fqn(existingFqn), ...
                      mip.parse.display_fqn(existingFqn));
            end
            pkgDir = mip.paths.get_package_dir(fqn);
            if exist(pkgDir, 'dir')
                fprintf('Package "%s" is already installed\n', mip.parse.display_fqn(fqn));
            else
                toInstallFqns{end+1} = fqn; %#ok<AGROW>
            end
        end

        % Show installation plan and install
        if ~isempty(toInstallFqns)
            if isscalar(toInstallFqns)
                fprintf('\nInstallation plan:\n');
            else
                fprintf('\nInstallation plan (%d packages):\n', length(toInstallFqns));
            end
            for i = 1:length(toInstallFqns)
                fprintf('  - %s %s\n', mip.parse.display_fqn(toInstallFqns{i}), packageInfoMap(toInstallFqns{i}).version);
            end
            fprintf('\n');

            installAttempted = true;
            for i = 1:length(toInstallFqns)
                fqn = toInstallFqns{i};
                pkgDir = mip.paths.get_package_dir(fqn);
                downloadAndInstall(fqn, packageInfoMap(fqn), pkgDir);
            end
        end
    catch ME
        fprintf('\nInstall failed; rolling back...\n');
        restoreReplacementBackups(replacementBackups);
        if installAttempted
            try
                mip.state.prune_unused_packages();
            catch pruneErr
                warning('mip:rollbackFailed', ...
                        'Rollback prune failed: %s', pruneErr.message);
            end
        end
        rethrow(ME);
    end
    cleanupReplacementBackups(replacementBackups);

    if ~isempty(toInstallFqns)
        for i = 1:length(resolvedPackages)
            s = resolvedPackages{i};
            if ismember(s.fqn, toInstallFqns)
                installedFqns{end+1} = s.fqn; %#ok<AGROW>
            end
        end
    end

    % Mark requested packages as directly installed. Runs whether or not
    % anything new was downloaded, so that re-installing a package that
    % was previously pulled in as a transitive dep promotes it. Skipped
    % when this call is installing transitive dependencies (e.g. from an
    % .mhl install) so those deps can be pruned later.
    if markDirectlyInstalled
        for i = 1:length(resolvedPackages)
            mip.state.add_directly_installed(resolvedPackages{i}.fqn);
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
                fprintf('  - %s\n', mip.parse.display_fqn(allInstalled{k}));
            end
        end
    end
end

function [reloadAfterInstall, replacementBackups] = replaceExistingVersions(resolvedPackages, packageInfoMap)
% Replace installed packages when the user requested a different @version.
% Old packages are moved to backup dirs (returned in replacementBackups) so the
% caller can restore them if a subsequent download/install fails.
% Returns FQNs that were loaded before replacement (caller should reload them).
    reloadAfterInstall = {};
    replacementBackups = struct('fqn', {}, 'pkgDir', {}, 'backupDir', {}, ...
                                'wasDirectlyInstalled', {});
    for i = 1:length(resolvedPackages)
        s = resolvedPackages{i};
        if isempty(s.requested_version)
            continue;
        end
        pkgDir = mip.paths.get_package_dir(s.fqn);
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
                mip.parse.display_fqn(s.fqn), installedInfo.version, s.requested_version);
        if mip.state.is_loaded(s.fqn)
            mip.unload(s.fqn);
            reloadAfterInstall{end+1} = s.fqn; %#ok<AGROW>
        end
        wasDirectlyInstalled = mip.state.is_directly_installed(s.fqn);
        backupDir = mip.paths.backup_dir(pkgDir);
        if wasDirectlyInstalled
            mip.state.remove_directly_installed(s.fqn);
        end
        replacementBackups(end+1) = struct(...
            'fqn', s.fqn, ...
            'pkgDir', pkgDir, ...
            'backupDir', backupDir, ...
            'wasDirectlyInstalled', wasDirectlyInstalled); %#ok<AGROW>
    end
end

function restoreReplacementBackups(replacementBackups)
% Restore packages from backup dirs after a failed replace install.
    for i = 1:length(replacementBackups)
        b = replacementBackups(i);
        try
            mip.paths.restore_dir(b.backupDir, b.pkgDir);
            if b.wasDirectlyInstalled
                mip.state.add_directly_installed(b.fqn);
            end
        catch restoreErr
            warning('mip:rollbackFailed', ...
                    'Could not restore "%s" from backup: %s', ...
                    mip.parse.display_fqn(b.fqn), restoreErr.message);
        end
    end
end

function cleanupReplacementBackups(replacementBackups)
% Remove backup dirs (the replaced old packages) after a successful replace
% install. These may carry binaries that were loaded before the replace, so
% route them through the robust trash-based removal.
    for i = 1:length(replacementBackups)
        b = replacementBackups(i);
        mip.paths.remove_dir(b.backupDir);
    end
end

function downloadAndInstall(fqn, packageInfo, pkgDir)
% Download and install a single package.

    fprintf('Downloading %s %s...\n', mip.parse.display_fqn(fqn), packageInfo.version);

    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    try
        expectedSha = '';
        if isfield(packageInfo, 'mhl_sha256')
            expectedSha = packageInfo.mhl_sha256;
        end
        mhlPath = mip.channel.download_mhl(packageInfo.mhl_url, tempDir, expectedSha);
        stagingDir = fullfile(tempDir, 'staging');
        mip.channel.extract_mhl(mhlPath, stagingDir);
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end
        movefile(stagingDir, pkgDir);
        fprintf('Successfully installed "%s"\n', mip.parse.display_fqn(fqn));
    catch ME
        if exist(pkgDir, 'dir')
            rmdir(pkgDir, 's');
        end
        rethrow(ME);
    end
end

function [bareChannels, skippedChannels] = resolveBareNameChannels(parsedArgs, priorityChannels)
% Walk priorityChannels in order. For each, fetch the channel's raw index
% and check which unresolved bare-name args appear in it. The first
% channel to publish a given bare name wins. Bare names not found in any
% priority channel are returned as ''; the caller defaults them and
% surfaces the consulted channel list in the "not found" error.
%
% A channel whose index cannot be fetched is logged via warning and
% skipped (returned in skippedChannels); resolution continues against
% the remaining channels rather than aborting the whole install.

    bareChannels = cell(1, length(parsedArgs));
    skippedChannels = {};
    for c = 1:length(priorityChannels)
        % Stop early once every bare-name arg has been placed.
        if ~anyUnresolved(parsedArgs, bareChannels)
            break
        end

        chSpec = priorityChannels{c};
        try
            chIndex = mip.channel.fetch_index(chSpec);
        catch ME
            warning('mip:channelUnreachable', ...
                    ['Could not fetch index for channel "%s" (%s). ' ...
                     'Skipping; bare-name resolution will continue with the remaining channels.'], ...
                    chSpec, ME.message);
            skippedChannels{end+1} = chSpec; %#ok<AGROW>
            continue
        end

        availableNorms = containers.Map('KeyType', 'char', 'ValueType', 'logical');
        if isfield(chIndex, 'packages')
            for k = 1:length(chIndex.packages)
                pkg = chIndex.packages{k};
                if isstruct(pkg) && isfield(pkg, 'name')
                    availableNorms(mip.name.normalize(pkg.name)) = true;
                end
            end
        end

        for j = 1:length(parsedArgs)
            parsed = parsedArgs{j};
            if parsed.is_fqn || ~isempty(bareChannels{j})
                continue
            end
            if availableNorms.isKey(mip.name.normalize(parsed.name))
                bareChannels{j} = chSpec;
            end
        end
    end
end

function tf = anyUnresolved(parsedArgs, bareChannels)
    tf = false;
    for j = 1:length(parsedArgs)
        if ~parsedArgs{j}.is_fqn && isempty(bareChannels{j})
            tf = true;
            return
        end
    end
end

function fetchChannelIndex(ch, packageInfoMap, unavailablePackages, fetchedChannels, requestedVersions)
% Fetch a channel's index and merge into the package info map.
    if fetchedChannels.isKey(ch)
        return
    end
    fprintf('Fetching package index for %s...\n', ch);
    [chOwner, chName] = mip.parse.parse_channel_spec(ch);
    chIndex = mip.channel.fetch_index(ch);
    % Project FQN-keyed requestedVersions down to name-keyed map for this channel
    chRequestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fqnKeys = keys(requestedVersions);
    for j = 1:length(fqnKeys)
        parsed = mip.parse.parse_package_arg(fqnKeys{j});
        if strcmp(parsed.owner, chOwner) && strcmp(parsed.channel, chName)
            chRequestedVersions(parsed.name) = requestedVersions(fqnKeys{j});
        end
    end
    [chMap, chUnavail] = mip.resolve.build_package_info_map(chIndex, chOwner, chName, chRequestedVersions);
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
