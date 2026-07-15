function lockData = lock_project(proj, upgrade)
%LOCK_PROJECT   Resolve a project's mip.yaml and write its mip.lock.
%
% The resolver behind "mip project lock" and the re-lock steps of
% "mip project add/remove/run". Resolves the spec's dependency list and
% every dependency group against mip-org/core plus the spec's channels,
% builds the combined dependency graph, and writes the full transitive
% closure to mip.lock in dependency-first order. It installs nothing,
% and downloads nothing beyond channel indexes; digests and hashes are
% copied from the channel index entries.
%
% Without upgrade, versions recorded in an existing mip.lock are kept
% when the channel still publishes them - re-locking after a spec edit
% does not silently upgrade unrelated packages. With upgrade, everything
% re-resolves to the newest permitted versions. Spec @version pins
% always win over both.
%
% Args:
%   proj    - Project struct from mip.project.locate
%   upgrade - Re-resolve to newest permitted versions
%
% Returns:
%   lockData - The lock struct written to mip.lock (see write_lock).

spec = mip.project.read_spec(proj.dir);

% Requirement sets: the base dependency list plus every group, in spec
% order. The lock records, per package, which sets require it, so sync
% can select groups without re-resolving.
groupNames = fieldnames(spec.dependency_groups)';
setDeps = [{spec.dependencies}, ...
           cellfun(@(g) spec.dependency_groups.(g), groupNames, 'UniformOutput', false)];
setLabels = [{''}, groupNames];

% Parse every request up front. Only GitHub channel packages can be
% locked: the lock reinstalls from .mhl URLs, which local/fex/web
% installs do not have.
requests = {};
for si = 1:numel(setDeps)
    deps = setDeps{si};
    for di = 1:numel(deps)
        parsed = mip.parse.parse_package_arg(deps{di});
        if parsed.is_fqn && ~strcmp(parsed.type, 'gh')
            error('mip:project:unsupportedDependency', ...
                  ['Cannot lock dependency "%s": only channel (GitHub) ' ...
                   'packages can be locked. Non-channel installs are not ' ...
                   'reproducible from a lockfile.'], deps{di});
        end
        requests{end+1} = struct('arg', deps{di}, 'parsed', parsed, 'set', si); %#ok<AGROW>
    end
end

% Channel priority list for bare names: mip-org/core first, then the
% spec's channels in listed order. The session's channel subscriptions
% are deliberately not consulted - only the committed spec drives the
% lock.
priorityChannels = {'mip-org/core'};
for i = 1:numel(spec.channels)
    if ~ismember(spec.channels{i}, priorityChannels)
        priorityChannels{end+1} = spec.channels{i}; %#ok<AGROW>
    end
end

fprintf('Resolving %d dependency spec(s)...\n', numel(requests));
currentArch = mip.build.arch();

% Raw indexes, fetched once per channel.
rawIndexes = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:numel(priorityChannels)
    rawIndexes(priorityChannels{i}) = mip.channel.fetch_index(priorityChannels{i});
end

% Resolve each request to a (provisional) FQN. A bare name goes to the
% first priority channel that publishes it.
for i = 1:numel(requests)
    r = requests{i};
    if r.parsed.is_fqn
        fqn = r.parsed.fqn;
    else
        ch = '';
        for c = 1:numel(priorityChannels)
            if index_has_name(rawIndexes(priorityChannels{c}), r.parsed.name)
                ch = priorityChannels{c};
                break
            end
        end
        if isempty(ch)
            error('mip:packageNotFound', ...
                  'Package "%s" not found in any of: %s', ...
                  r.parsed.name, strjoin(priorityChannels, ', '));
        end
        [chOwner, chName] = mip.parse.parse_channel_spec(ch);
        fqn = mip.parse.make_fqn(chOwner, chName, r.parsed.name);
    end
    requests{i}.fqn = fqn;
    ensure_raw_index(rawIndexes, fqn);
end

% Requested versions, FQN-keyed. Spec @version pins first (conflicting
% pins for one package are an error) ...
requestedVersions = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:numel(requests)
    r = requests{i};
    if isempty(r.parsed.version)
        continue
    end
    if requestedVersions.isKey(r.fqn) && ...
            ~strcmp(requestedVersions(r.fqn), r.parsed.version)
        error('mip:project:conflictingPins', ...
              ['mip.yaml pins "%s" to both %s and %s. Pin one version ' ...
               'across the dependency lists.'], ...
              mip.parse.display_fqn(r.fqn), ...
              requestedVersions(r.fqn), r.parsed.version);
    end
    requestedVersions(r.fqn) = r.parsed.version;
end

% ... then, unless upgrading, versions preserved from the existing lock
% (transitive dependencies included), when the channel still publishes
% them.
if ~upgrade && isfile(proj.lock_path)
    try
        prev = mip.project.read_lock(proj.lock_path);
    catch ME
        warning('mip:project:lockUnreadable', ...
                'Ignoring existing mip.lock (%s); resolving fresh.', ME.message);
        prev = struct('packages', {{}});
    end
    for i = 1:numel(prev.packages)
        p = prev.packages{i};
        if requestedVersions.isKey(p.fqn) || isempty(p.version)
            continue
        end
        try
            ensure_raw_index(rawIndexes, p.fqn);
        catch
            continue  % channel gone; let this package re-resolve
        end
        parsed = mip.parse.parse_package_arg(p.fqn);
        idx = rawIndexes([parsed.owner '/' parsed.channel]);
        if index_has_version(idx, p.name, p.version)
            requestedVersions(p.fqn) = p.version;
        end
    end
end

% Build the combined package info map from every fetched channel, with
% requested versions applied.
packageInfoMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
unavailablePackages = containers.Map('KeyType', 'char', 'ValueType', 'any');
builtChannels = containers.Map('KeyType', 'char', 'ValueType', 'logical');
chKeys = keys(rawIndexes);
for i = 1:numel(chKeys)
    build_channel_map(chKeys{i}, rawIndexes, packageInfoMap, ...
                      unavailablePackages, builtChannels, requestedVersions);
end

% Canonicalize request FQNs to the channel-published names, and verify
% every request is available for this architecture.
requestFqns = {};
for i = 1:numel(requests)
    canonical = mip.resolve.canonicalize_in_map(requests{i}.fqn, packageInfoMap);
    requests{i}.fqn = canonical;
    if ~packageInfoMap.isKey(canonical)
        if unavailablePackages.isKey(canonical)
            archs = unavailablePackages(canonical);
            error('mip:packageUnavailable', ...
                  ['Package "%s" is not available for architecture "%s". ' ...
                   'Available architectures: %s'], ...
                  mip.parse.display_fqn(canonical), currentArch, ...
                  strjoin(archs, ', '));
        end
        error('mip:packageNotFound', ...
              'Package "%s" not found in repository', ...
              mip.parse.display_fqn(canonical));
    end
    if ~ismember(canonical, requestFqns)
        requestFqns{end+1} = canonical; %#ok<AGROW>
    end
end

% Build the dependency graph per request, fetching cross-channel
% dependency indexes on demand and retrying (as remote install does).
setClosures = cell(1, numel(setDeps));
for attempt = 1:10
    allFqns = {};
    allMissing = {};
    for si = 1:numel(setDeps)
        setClosures{si} = {};
    end
    for i = 1:numel(requests)
        [order, missing] = mip.dependency.build_graph(requests{i}.fqn, packageInfoMap);
        si = requests{i}.set;
        setClosures{si} = [setClosures{si}, order];
        allFqns = [allFqns, order]; %#ok<AGROW>
        allMissing = [allMissing, missing]; %#ok<AGROW>
    end
    allMissing = unique(allMissing, 'stable');
    if isempty(allMissing)
        break
    end

    fetchedNew = false;
    for i = 1:numel(allMissing)
        parsed = mip.parse.parse_package_arg(allMissing{i});
        if ~parsed.is_fqn || ~strcmp(parsed.type, 'gh')
            error('mip:packageNotFound', ...
                  'Package "%s" not found in repository', ...
                  mip.parse.display_fqn(allMissing{i}));
        end
        ch = [parsed.owner '/' parsed.channel];
        if builtChannels.isKey(ch)
            continue
        end
        fprintf('Fetching %s index for cross-channel dependency...\n', ch);
        ensure_raw_index(rawIndexes, allMissing{i});
        build_channel_map(ch, rawIndexes, packageInfoMap, ...
                          unavailablePackages, builtChannels, requestedVersions);
        fetchedNew = true;
    end
    if ~fetchedNew
        missingDisplay = cellfun(@mip.parse.display_fqn, allMissing, 'UniformOutput', false);
        error('mip:packageNotFound', ...
              'Package(s) not found in repository: %s', ...
              strjoin(missingDisplay, ', '));
    end
end

allFqns = unique(allFqns, 'stable');
sortedFqns = mip.dependency.topological_sort(allFqns, packageInfoMap);

% Assemble the lock entries in dependency-first order.
entries = cell(1, numel(sortedFqns));
for i = 1:numel(sortedFqns)
    fqn = sortedFqns{i};
    info = packageInfoMap(fqn);
    e = struct();
    e.fqn = fqn;
    e.name = info.name;
    e.version = info.version;
    e.architecture = field_or(info, 'architecture', 'any');
    e.mhl_url = field_or(info, 'mhl_url', '');
    e.mhl_sha256 = field_or(info, 'mhl_sha256', '');
    e.commit_hash = field_or(info, 'commit_hash', '');
    e.source_hash = field_or(info, 'source_hash', '');
    e.dependencies = as_cellstr(field_or(info, 'dependencies', {}));
    e.direct = ismember(fqn, requestFqns);
    e.base = ismember(fqn, setClosures{1});
    e.groups = {};
    for si = 2:numel(setDeps)
        if ismember(fqn, setClosures{si})
            e.groups{end+1} = setLabels{si};
        end
    end
    entries{i} = e;
end

lockData = struct();
lockData.lock_version = 1;
lockData.mip_version = mip.version();
lockData.spec_sha256 = mip.project.spec_hash(proj.dir);
lockData.packages = entries;

mip.project.write_lock(proj.lock_path, lockData);

nDirect = sum(cellfun(@(e) e.direct, entries));
fprintf('Locked %d package(s) (%d direct) -> %s\n', ...
        numel(entries), nDirect, mip.env.display_path(proj.lock_path));

end

function ensure_raw_index(rawIndexes, fqnOrChannel)
% Fetch (once) the raw index for the channel of an FQN, or for a
% '<owner>/<channel>' spec.
    if contains(fqnOrChannel, '/') && ~startsWith(fqnOrChannel, 'gh/') ...
            && numel(strsplit(fqnOrChannel, '/')) == 2
        ch = fqnOrChannel;
    else
        parsed = mip.parse.parse_package_arg(fqnOrChannel);
        ch = [parsed.owner '/' parsed.channel];
    end
    if ~rawIndexes.isKey(ch)
        rawIndexes(ch) = mip.channel.fetch_index(ch);
    end
end

function build_channel_map(ch, rawIndexes, packageInfoMap, unavailablePackages, builtChannels, requestedVersions)
% Merge one channel's best-variant info into the combined map, honoring
% FQN-keyed requested versions (projected down to bare names for this
% channel, as remote install does).
    if builtChannels.isKey(ch)
        return
    end
    [chOwner, chName] = mip.parse.parse_channel_spec(ch);
    chRequested = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fqnKeys = keys(requestedVersions);
    for j = 1:numel(fqnKeys)
        parsed = mip.parse.parse_package_arg(fqnKeys{j});
        if strcmp(parsed.owner, chOwner) && strcmp(parsed.channel, chName)
            chRequested(parsed.name) = requestedVersions(fqnKeys{j});
        end
    end
    [chMap, chUnavail] = mip.resolve.build_package_info_map( ...
        rawIndexes(ch), chOwner, chName, chRequested);
    ks = keys(chMap);
    for j = 1:numel(ks)
        packageInfoMap(ks{j}) = chMap(ks{j});
    end
    ks = keys(chUnavail);
    for j = 1:numel(ks)
        unavailablePackages(ks{j}) = chUnavail(ks{j});
    end
    builtChannels(ch) = true;
end

function tf = index_has_name(index, name)
% True when the raw channel index publishes a package equivalent to name.
    tf = false;
    if ~isfield(index, 'packages')
        return
    end
    pkgs = index.packages;
    for k = 1:numel(pkgs)
        pkg = get_entry(pkgs, k);
        if isstruct(pkg) && isfield(pkg, 'name') && mip.name.match(pkg.name, name)
            tf = true;
            return
        end
    end
end

function tf = index_has_version(index, name, version)
% True when the raw channel index publishes the given version of name.
    tf = false;
    if ~isfield(index, 'packages')
        return
    end
    pkgs = index.packages;
    for k = 1:numel(pkgs)
        pkg = get_entry(pkgs, k);
        if isstruct(pkg) && isfield(pkg, 'name') && isfield(pkg, 'version') ...
                && mip.name.match(pkg.name, name) && strcmp(pkg.version, version)
            tf = true;
            return
        end
    end
end

function e = get_entry(pkgs, k)
    if iscell(pkgs)
        e = pkgs{k};
    else
        e = pkgs(k);
    end
end

function v = field_or(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    else
        v = default;
    end
end

function v = as_cellstr(v)
    if isempty(v)
        v = {};
    elseif ischar(v)
        v = {v};
    elseif isstring(v)
        v = cellstr(v);
    elseif iscell(v)
        for i = 1:numel(v)
            v{i} = char(v{i});
        end
    end
    v = reshape(v, 1, []);
end
