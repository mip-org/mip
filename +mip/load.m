function load(varargin)
%LOAD   Load one or more mip packages into the MATLAB path.
%
% Usage:
%   mip load <package>
%   mip load <package1> <package2> ...
%   mip load <package> --sticky
%   mip load <package> --install
%   mip load --channel <owner>/<channel> <package> --install
%   mip load <owner>/<channel>/<package>
%
% Accepts both bare package names and fully qualified names (owner/channel/package).
% For bare names, resolution priority is:
%   1. mip-org/core
%   2. First alphabetically by owner/channel
%
% Options:
%   --sticky         Mark the package(s) as sticky (prevents unload with 'mip unload --all')
%   --install        Automatically install the package(s) if not already installed
%   --channel <name> Channel to install from when using --install
%   --addpath <rel>  Add this source-relative subpath to the MATLAB path AFTER
%                    the paths from mip.json are added. May be repeated. Only
%                    valid with a single positional package; applies only to
%                    direct loads (not transitive dependencies).
%   --rmpath  <rel>  Remove this source-relative subpath from the MATLAB path
%                    AFTER the paths from mip.json are added. Same constraints
%                    as --addpath.
%   --with <group>   Also add to the MATLAB path the directories declared
%                    under extra_paths.<group> in the package's mip.yaml
%                    (e.g. --with examples, --with tests). May be repeated.
%                    Applies only to direct loads. Warns at end if no loaded
%                    package declared the requested group.
%   --transitive     (internal) Load as a transitive dependency, not a direct load

    % Parse flags and package names from arguments
    installIfMissing = false;
    stickyPackage = false;
    isDirect = true;
    channel = '';
    addPathRels = {};
    rmPathRels = {};
    withGroups = {};
    packageArgs = {};
    i = 1;
    while i <= length(varargin)
        arg = varargin{i};
        if ischar(arg) && strcmp(arg, '--install')
            installIfMissing = true;
        elseif ischar(arg) && strcmp(arg, '--sticky')
            stickyPackage = true;
        elseif ischar(arg) && strcmp(arg, '--transitive')
            isDirect = false;
        elseif ischar(arg) && strcmp(arg, '--channel')
            if i < length(varargin)
                i = i + 1;
                channel = varargin{i};
            else
                error('mip:load:missingChannel', '--channel requires a value');
            end
        elseif ischar(arg) && strcmp(arg, '--addpath')
            if i < length(varargin)
                i = i + 1;
                addPathRels{end+1} = varargin{i}; %#ok<*AGROW>
            else
                error('mip:load:missingAddpathValue', '--addpath requires a value');
            end
        elseif ischar(arg) && strcmp(arg, '--rmpath')
            if i < length(varargin)
                i = i + 1;
                rmPathRels{end+1} = varargin{i};
            else
                error('mip:load:missingRmpathValue', '--rmpath requires a value');
            end
        elseif ischar(arg) && strcmp(arg, '--with')
            if i < length(varargin)
                i = i + 1;
                withGroups{end+1} = varargin{i};
            else
                error('mip:load:missingWithValue', '--with requires a group name');
            end
        elseif ischar(arg) && ~startsWith(arg, '--')
            packageArgs{end+1} = arg;
        end
        i = i + 1;
    end

    if isempty(packageArgs)
        error('mip:noPackage', 'No package specified for load command.');
    end

    if (~isempty(addPathRels) || ~isempty(rmPathRels)) && length(packageArgs) > 1
        error('mip:load:addpathSinglePackage', ...
              ['--addpath / --rmpath require exactly one positional package; ' ...
               'got %d. The flags resolve relative to that package''s source ' ...
               'directory.'], length(packageArgs));
    end

    % Load each package. --addpath/--rmpath/--with only flow into direct
    % loads; they are intentionally not propagated to transitive
    % dependencies. matchedGroups accumulates the --with groups that
    % were actually declared by at least one loaded package, so we can
    % warn at the end about groups that matched nothing.
    matchedGroups = {};
    for i = 1:length(packageArgs)
        if isDirect
            matched = loadSingle(packageArgs{i}, installIfMissing, stickyPackage, ...
                       channel, isDirect, {}, addPathRels, rmPathRels, withGroups);
            matchedGroups = [matchedGroups, matched];
        else
            loadSingle(packageArgs{i}, installIfMissing, stickyPackage, ...
                       channel, isDirect, {}, {}, {}, {});
        end
    end

    for k = 1:length(withGroups)
        g = withGroups{k};
        if ~ismember(g, matchedGroups)
            warning('mip:load:unknownGroup', ...
                    ['No loaded package declares the extra path group "%s". ' ...
                     '"--with %s" had no effect.'], g, g);
        end
    end
end

function matched = loadSingle(packageArg, installIfMissing, stickyPackage, channel, isDirect, loadingStack, addPathRels, rmPathRels, withGroups)
% Load a single package (and its dependencies recursively).
%
% addPathRels / rmPathRels: cell arrays of source-relative paths to
% addpath / rmpath after the mip.json paths are applied. Only honored
% for direct loads (the recursive call for dependencies passes empty).
%
% withGroups: cell array of extra_paths group names to also add to the
% MATLAB path. Only honored for direct loads. Returns the subset that
% this package actually declared (used by the caller to warn about
% groups that matched nothing across the whole load).

    matched = {};

    % Resolve the FQN for this package, installing first if requested
    try
        fqn = resolveToFqn(packageArg);
    catch ME
        if installIfMissing && strcmp(ME.identifier, 'mip:packageNotFound')
            fprintf('Package "%s" is not installed. Installing...\n', packageArg);
            if ~isempty(channel)
                mip.install('--channel', channel, packageArg);
            else
                mip.install(packageArg);
            end
            fqn = resolveToFqn(packageArg);
        else
            rethrow(ME);
        end
    end

    % gh/mip-org/core/mip is always loaded — nothing to do
    if strcmp(fqn, 'gh/mip-org/core/mip')
        fprintf('Package "mip" is always loaded\n');
        return
    end

    displayFqn = mip.parse.display_fqn(fqn);

    % Check for circular dependencies
    if ismember(fqn, loadingStack)
        cycleDisplay = cellfun(@mip.parse.display_fqn, [loadingStack, {fqn}], 'UniformOutput', false);
        cycle = strjoin(cycleDisplay, ' -> ');
        error('mip:circularDependency', ...
              'Circular dependency detected: %s', cycle);
    end

    % Add to loading stack for circular dependency detection
    loadingStack = [loadingStack, {fqn}];

    % Compute package directory from the canonical FQN
    packageDir = mip.paths.get_package_dir(fqn);

    % Check if package exists
    if ~mip.state.is_installed(fqn)
        error('mip:packageNotFound', ...
              'Package "%s" is not installed. Run "mip install %s" first.', ...
              displayFqn, displayFqn);
    end

    % Check if package is already loaded
    if mip.state.is_loaded(fqn)
        % If this is a direct load and the package was previously
        % loaded as a dependency, mark it as direct now
        if isDirect && ~mip.state.is_directly_loaded(fqn)
            mip.state.key_value_append('MIP_DIRECTLY_LOADED_PACKAGES', fqn);
            fprintf('Package "%s" is already loaded (now marked as direct)\n', displayFqn);
        else
            fprintf('Package "%s" is already loaded\n', displayFqn);
        end
        if isDirect
            mip.state.add_directly_installed(fqn);
        end
        % If --sticky was specified, add to sticky packages
        if stickyPackage
            if ~mip.state.is_sticky(fqn)
                mip.state.key_value_append('MIP_STICKY_PACKAGES', fqn);
                fprintf('Package "%s" is now sticky\n', displayFqn);
            end
        end
        % Apply --addpath/--rmpath/--with even when already loaded so
        % the user can adjust the path of an existing load without
        % re-loading.
        applyPathAdjustments(packageDir, addPathRels, rmPathRels);
        matched = applyExtraPaths(packageDir, withGroups);
        return
    end

    % Load dependencies listed in mip.json. Only the parse step is
    % wrapped in try/catch so that recursive dependency-load errors propagate
    % instead of being silently downgraded to a warning.
    mipJsonPath = fullfile(packageDir, 'mip.json');
    deps = {};
    mipConfig = [];
    if exist(mipJsonPath, 'file')
        try
            mipConfig = mip.config.read_package_json(packageDir);
            deps = mipConfig.dependencies;
        catch ME
            % Path-traversal failures must propagate so a malicious
            % package cannot fall through to the addpath stage.
            if strcmp(ME.identifier, 'mip:unsafePath')
                rethrow(ME);
            end
            warning('mip:jsonParseError', ...
                    'Could not parse mip.json for package "%s": %s', ...
                    displayFqn, ME.message);
        end
    end

    if ~isempty(deps)
        fprintf('Loading dependencies for "%s": %s\n', ...
                displayFqn, strjoin(deps, ', '));
        for i = 1:length(deps)
            dep = deps{i};
            depFqn = mip.resolve.resolve_dependency(dep);
            if ~mip.state.is_loaded(depFqn)
                loadSingle(depFqn, installIfMissing, false, channel, false, loadingStack, {}, {}, {});
            else
                fprintf('  Dependency "%s" is already loaded\n', mip.parse.display_fqn(depFqn));
            end
        end
    end

    % Add paths from mip.json.
    if isempty(mipConfig) || ~isfield(mipConfig, 'paths')
        error('mip:loadNotFound', ...
              'Package "%s" has no "paths" field in mip.json', displayFqn);
    end
    applyMipJsonPaths(packageDir, mipConfig);

    fprintf('Loaded package "%s"\n', displayFqn);

    % Apply --addpath / --rmpath after the mip.json paths have been added.
    applyPathAdjustments(packageDir, addPathRels, rmPathRels);
    matched = applyExtraPaths(packageDir, withGroups);

    % Mark package as loaded
    mip.state.key_value_append('MIP_LOADED_PACKAGES', fqn);

    % Track directly loaded packages separately
    if isDirect
        mip.state.key_value_append('MIP_DIRECTLY_LOADED_PACKAGES', fqn);
        mip.state.add_directly_installed(fqn);
    end

    % Mark package as sticky if requested
    if stickyPackage
        mip.state.key_value_append('MIP_STICKY_PACKAGES', fqn);
        fprintf('Package "%s" is now sticky\n', displayFqn);
    end
end

function applyMipJsonPaths(packageDir, pkgInfo)
% addpath each entry in pkgInfo.paths against the package source
% directory. Silent on success -- the "Loaded package" summary is
% printed by the caller.
    if isempty(pkgInfo.paths)
        return
    end
    srcDir = mip.paths.get_source_dir(packageDir, pkgInfo);
    for i = 1:length(pkgInfo.paths)
        rel = pkgInfo.paths{i};
        mip.paths.assert_safe_relative(rel, sprintf('mip.json paths[%d]', i));
        if strcmp(rel, '.')
            target = srcDir;
        else
            target = fullfile(srcDir, rel);
        end
        addpath(target);
    end
end

function matched = applyExtraPaths(packageDir, withGroups)
% For each requested group, if the package declares extra_paths.<group>
% in its mip.json, addpath each entry relative to the source directory.
% Returns the subset of withGroups this package actually declared.

    matched = {};
    if isempty(withGroups)
        return
    end

    pkgInfo = mip.config.read_package_json(packageDir);
    if ~isfield(pkgInfo, 'extra_paths') || ~isstruct(pkgInfo.extra_paths)
        return
    end
    srcDir = mip.paths.get_source_dir(packageDir, pkgInfo);

    for i = 1:length(withGroups)
        group = withGroups{i};
        if ~isfield(pkgInfo.extra_paths, group)
            continue
        end
        paths = pkgInfo.extra_paths.(group);
        for j = 1:length(paths)
            rel = paths{j};
            mip.paths.assert_safe_relative(rel, ...
                sprintf('mip.json extra_paths.%s[%d]', group, j));
            if strcmp(rel, '.')
                target = srcDir;
            else
                target = fullfile(srcDir, rel);
            end
            addpath(target);
        end
        matched{end+1} = group; %#ok<AGROW>
    end
end

function applyPathAdjustments(packageDir, addPathRels, rmPathRels)
% Apply --addpath / --rmpath relative to the package's source directory.
% No-op if both lists are empty.

    if isempty(addPathRels) && isempty(rmPathRels)
        return
    end

    pkgInfo = mip.config.read_package_json(packageDir);
    srcDir = mip.paths.get_source_dir(packageDir, pkgInfo);

    for i = 1:length(addPathRels)
        rel = addPathRels{i};
        mip.paths.assert_safe_relative(rel, '--addpath');
        target = fullfile(srcDir, rel);
        % addpath emits MATLAB:addpath:DirNotFound if the target is missing.
        addpath(target);
        fprintf('  +addpath %s\n', target);
    end

    for i = 1:length(rmPathRels)
        rel = rmPathRels{i};
        mip.paths.assert_safe_relative(rel, '--rmpath');
        target = fullfile(srcDir, rel);
        % rmpath warns (not errors) if the path is not on the search path.
        rmpath(target);
        fprintf('  -rmpath %s\n', target);
    end
end

function fqn = resolveToFqn(packageArg)
% Resolve a package argument to a fully qualified name.
% If already FQN, canonicalize the name component to its on-disk form.
% If bare name, look up installed packages.

    result = mip.parse.parse_package_arg(packageArg);

    if result.is_fqn
        % Canonicalize: find the actual on-disk name (case- and
        % dash/underscore-insensitive) so the rest of load uses the
        % canonical form, matching what's already in the loaded/sticky
        % state lists.
        onDisk = mip.resolve.installed_dir(result.fqn);
        if isempty(onDisk)
            error('mip:packageNotFound', ...
                  'Package "%s" is not installed. Run "mip install %s" first.', ...
                  packageArg, packageArg);
        end
        if strcmp(result.type, 'gh')
            fqn = mip.parse.make_fqn(result.owner, result.channel, onDisk);
        else
            fqn = [result.type '/' onDisk];
        end
    else
        % Resolve bare name to installed FQN
        fqn = mip.resolve.resolve_bare_name(result.name);
        if isempty(fqn)
            error('mip:packageNotFound', ...
                  'Package "%s" is not installed. Run "mip install %s" first.', ...
                  result.name, result.name);
        end
    end
end

