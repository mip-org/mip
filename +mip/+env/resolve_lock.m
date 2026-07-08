function lockData = resolve_lock(spec)
%RESOLVE_LOCK   Resolve a spec's dependencies into a full, pinned lock.
%
% Args:
%   spec - Spec struct from mip.env.read_spec (dependencies + channels).
%
% Returns:
%   lockData - Struct ready to serialize to mipenv.lock:
%       .lock_version       - lock format version (integer)
%       .generated_with_mip - mip version string that produced the lock
%       .arch               - architecture the lock was resolved for
%       .requested          - the spec's dependency list (verbatim)
%       .channels           - channels consulted, in priority order
%       .packages           - cell array of resolved package entries, in
%                             install (dependencies-first) order, each with:
%                               fqn, name, owner, channel, version,
%                               architecture, mhl_url, mhl_sha256,
%                               source_hash, commit_hash, dependencies
%
% This walks the same channel indexes the normal installer uses and reuses
% mip.resolve / mip.dependency to compute the full transitive closure with
% concrete versions, so the lock captures exactly what a reproducing
% install must fetch. Call within a mip.env.with_root context so index
% fetches cache into the project environment.

    currentArch = mip.build.arch();

    % Priority channel list: core first, then the spec's extra channels.
    priorityChannels = [{'mip-org/core'}, reshape(spec.channels, 1, [])];
    priorityChannels = unique_stable(priorityChannels);

    % Parse each dependency; collect FQN->version pins from @version suffixes.
    deps = spec.dependencies;
    if isempty(deps)
        error('mip:env:emptySpec', ...
              ['The environment has no dependencies. Add some with ' ...
               '"mip env add <package>" or edit mipenv.yaml.']);
    end
    parsed = cell(1, numel(deps));
    requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:numel(deps)
        parsed{i} = mip.parse.parse_package_arg(deps{i});
    end

    % Fetch the priority channels plus any channel named by an FQN dep, and
    % merge them into one FQN -> variant map.
    packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fetched = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    for c = 1:numel(priorityChannels)
        merge_channel(priorityChannels{c}, packageInfoMap, fetched, requestedVersions);
    end
    for i = 1:numel(parsed)
        if parsed{i}.is_fqn
            merge_channel([parsed{i}.owner '/' parsed{i}.channel], ...
                          packageInfoMap, fetched, requestedVersions);
        end
    end

    % Resolve every dependency argument to a concrete channel-canonical FQN.
    rootFqns = {};
    for i = 1:numel(deps)
        p = parsed{i};
        if p.is_fqn
            effChannel = [p.owner '/' p.channel];
        else
            effChannel = pick_bare_channel(p.name, priorityChannels, packageInfoMap);
        end
        [owner, ch, name, version] = mip.resolve.resolve_package_name(deps{i}, effChannel);
        fqn = mip.parse.make_fqn(owner, ch, name);
        canonical = mip.resolve.canonicalize_in_map(fqn, packageInfoMap);
        if ~packageInfoMap.isKey(canonical)
            error('mip:env:packageNotFound', ...
                  'Dependency "%s" not found for architecture "%s" in: %s', ...
                  deps{i}, currentArch, strjoin(priorityChannels, ', '));
        end
        if ~isempty(version)
            requestedVersions(canonical) = version;
        end
        rootFqns{end+1} = canonical; %#ok<AGROW>
    end

    % Re-merge channels now that @version pins on canonical FQNs are known,
    % so build_package_info_map selects the requested versions.
    packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fetched = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    channelsToFetch = priorityChannels;
    for i = 1:numel(rootFqns)
        p = mip.parse.parse_package_arg(rootFqns{i});
        channelsToFetch{end+1} = [p.owner '/' p.channel]; %#ok<AGROW>
    end
    channelsToFetch = unique_stable(channelsToFetch);
    for c = 1:numel(channelsToFetch)
        merge_channel(channelsToFetch{c}, packageInfoMap, fetched, requestedVersions);
    end

    % Build the combined dependency graph, fetching channels for any missing
    % cross-channel dependency and retrying (mirrors the installer's planner).
    allFqns = {};
    for attempt = 1:10
        allFqns = {};
        missing = {};
        for i = 1:numel(rootFqns)
            [order, miss] = mip.dependency.build_graph(rootFqns{i}, packageInfoMap);
            allFqns = [allFqns, order]; %#ok<AGROW>
            missing = [missing, miss]; %#ok<AGROW>
        end
        missing = unique_stable(missing);
        if isempty(missing)
            break
        end
        fetchedNew = false;
        for i = 1:numel(missing)
            mp = mip.parse.parse_package_arg(missing{i});
            if ~mp.is_fqn || ~strcmp(mp.type, 'gh')
                error('mip:env:packageNotFound', ...
                      'Dependency "%s" not found in repository', ...
                      mip.parse.display_fqn(missing{i}));
            end
            ch = [mp.owner '/' mp.channel];
            if fetched.isKey(ch)
                continue
            end
            merge_channel(ch, packageInfoMap, fetched, requestedVersions);
            fetchedNew = true;
        end
        if ~fetchedNew
            disp_missing = cellfun(@mip.parse.display_fqn, missing, 'UniformOutput', false);
            error('mip:env:packageNotFound', ...
                  'Dependencies not found in repository: %s', strjoin(disp_missing, ', '));
        end
    end
    allFqns = unique_stable(allFqns);
    allFqns = mip.dependency.topological_sort(allFqns, packageInfoMap);

    % Emit a lock entry per resolved package. Packages named directly by the
    % spec are flagged "direct" so sync can record them as directly-installed
    % (the rest are transitive dependencies, prunable when their parent goes).
    packages = {};
    for i = 1:numel(allFqns)
        fqn = allFqns{i};
        info = packageInfoMap(fqn);
        p = mip.parse.parse_package_arg(fqn);
        packages{end+1} = lock_entry(fqn, p, info, ismember(fqn, rootFqns)); %#ok<AGROW>
    end

    lockData = struct();
    lockData.lock_version = 1;
    lockData.generated_with_mip = mip.version();
    lockData.arch = currentArch;
    lockData.requested = reshape(deps, 1, []);
    lockData.channels = priorityChannels;
    lockData.packages = packages;
end

function entry = lock_entry(fqn, parsedFqn, info, isDirect)
% Build a single lock entry from an index variant struct.
    entry = struct();
    entry.fqn = fqn;
    entry.name = parsedFqn.name;
    entry.owner = parsedFqn.owner;
    entry.channel = parsedFqn.channel;
    entry.direct = logical(isDirect);
    entry.version = get_field(info, 'version', '');
    entry.architecture = get_field(info, 'architecture', '');
    entry.mhl_url = get_field(info, 'mhl_url', '');
    entry.mhl_sha256 = get_field(info, 'mhl_sha256', '');
    entry.source_hash = get_field(info, 'source_hash', '');
    entry.commit_hash = get_field(info, 'commit_hash', '');
    d = get_field(info, 'dependencies', {});
    if ~iscell(d)
        d = {d};
    end
    entry.dependencies = reshape(d, 1, []);
end

function merge_channel(channelSpec, packageInfoMap, fetched, requestedVersions)
% Fetch one channel index and merge its FQN->variant entries into the map.
    if fetched.isKey(channelSpec)
        return
    end
    [owner, name] = mip.parse.parse_channel_spec(channelSpec);
    index = mip.channel.fetch_index(channelSpec);
    % Project FQN-keyed pins down to this channel's name-keyed pins.
    chReq = containers.Map('KeyType', 'char', 'ValueType', 'any');
    ks = keys(requestedVersions);
    for j = 1:numel(ks)
        p = mip.parse.parse_package_arg(ks{j});
        if strcmp(p.owner, owner) && strcmp(p.channel, name)
            chReq(p.name) = requestedVersions(ks{j});
        end
    end
    chMap = mip.resolve.build_package_info_map(index, owner, name, chReq);
    mk = keys(chMap);
    for j = 1:numel(mk)
        packageInfoMap(mk{j}) = chMap(mk{j});
    end
    fetched(channelSpec) = true;
end

function ch = pick_bare_channel(bareName, priorityChannels, packageInfoMap)
% First channel in priority order that publishes bareName (case- and
% separator-insensitive). Falls back to core, which yields a clear
% "not found" error downstream if the name is truly absent.
    target = mip.name.normalize(bareName);
    for c = 1:numel(priorityChannels)
        [owner, name] = mip.parse.parse_channel_spec(priorityChannels{c});
        mk = keys(packageInfoMap);
        for j = 1:numel(mk)
            p = mip.parse.parse_package_arg(mk{j});
            if strcmp(p.owner, owner) && strcmp(p.channel, name) && ...
                    strcmp(mip.name.normalize(p.name), target)
                ch = priorityChannels{c};
                return
            end
        end
    end
    ch = 'mip-org/core';
end

function out = unique_stable(items)
    out = {};
    seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    for i = 1:numel(items)
        if isempty(items{i}) || seen.isKey(items{i})
            continue
        end
        seen(items{i}) = true;
        out{end+1} = items{i}; %#ok<AGROW>
    end
end

function v = get_field(s, f, default)
    if isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = default;
    end
end
