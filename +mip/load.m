function load(varargin)
%LOAD   Load one or more mip packages into the MATLAB path.
%
% Usage:
%   mip.load('packageName')
%   mip.load('package1', 'package2', ...)
%   mip.load('packageName', '--sticky')
%   mip.load('packageName', '--install')
%   mip.load('--channel', 'owner/chan', 'packageName', '--install')
%   mip.load('org/channel/packageName')
%
% Accepts both bare package names and fully qualified names (org/channel/package).
% For bare names, resolution priority is:
%   1. mip-org/core
%   2. First alphabetically by org/channel
%
% Options:
%   --sticky      Mark the package(s) as sticky (prevents unload with 'mip unload --all')
%   --install     Automatically install the package(s) if not already installed
%   --channel <c> Channel to install from when using --install (e.g. 'mip-org/staging')

    % Parse flags and package names from arguments
    installIfMissing = false;
    stickyPackage = false;
    channel = '';
    packageArgs = {};
    i = 1;
    while i <= length(varargin)
        arg = varargin{i};
        if ischar(arg) && strcmp(arg, '--install')
            installIfMissing = true;
        elseif ischar(arg) && strcmp(arg, '--sticky')
            stickyPackage = true;
        elseif ischar(arg) && strcmp(arg, '--channel')
            if i < length(varargin)
                i = i + 1;
                channel = varargin{i};
            else
                error('mip:load:missingChannel', '--channel requires a value');
            end
        elseif ischar(arg) && ~startsWith(arg, '--')
            packageArgs{end+1} = arg; %#ok<*AGROW>
        end
        i = i + 1;
    end

    if isempty(packageArgs)
        error('mip:noPackage', 'No package specified for load command.');
    end

    % Load each package
    for i = 1:length(packageArgs)
        loadSingle(packageArgs{i}, installIfMissing, stickyPackage, channel, true, {});
    end
end

function loadSingle(packageArg, installIfMissing, stickyPackage, channel, isDirect, loadingStack)
% Load a single package (and its dependencies recursively).

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

    % mip-org/core/mip is always loaded — nothing to do
    if strcmp(fqn, 'mip-org/core/mip')
        fprintf('Package "mip" is always loaded\n');
        return
    end

    % Check for circular dependencies
    if ismember(fqn, loadingStack)
        cycle = strjoin([loadingStack, {fqn}], ' -> ');
        error('mip:circularDependency', ...
              'Circular dependency detected: %s', cycle);
    end

    % Add to loading stack for circular dependency detection
    loadingStack = [loadingStack, {fqn}];

    % Parse FQN to get package directory
    result = mip.utils.parse_package_arg(fqn);
    packageDir = mip.utils.get_package_dir(result.org, result.channel, result.name);

    % Check if package exists
    if ~exist(packageDir, 'dir')
        error('mip:packageNotFound', ...
              'Package "%s" is not installed. Run "mip install %s" first.', ...
              fqn, fqn);
    end

    % Check if package is already loaded
    if mip.utils.is_loaded(fqn)
        % If this is a direct load and the package was previously
        % loaded as a dependency, mark it as direct now
        if isDirect && ~mip.utils.is_directly_loaded(fqn)
            mip.utils.key_value_append('MIP_DIRECTLY_LOADED_PACKAGES', fqn);
            fprintf('Package "%s" is already loaded (now marked as direct)\n', fqn);
        else
            fprintf('Package "%s" is already loaded\n', fqn);
        end
        % If --sticky was specified, add to sticky packages
        if stickyPackage
            if ~mip.utils.is_sticky(fqn)
                mip.utils.key_value_append('MIP_STICKY_PACKAGES', fqn);
                fprintf('Package "%s" is now sticky\n', fqn);
            end
        end
        return
    end

    % Load dependencies listed in mip.json. Only the parse step is
    % wrapped in try/catch so that recursive dependency-load errors propagate
    % instead of being silently downgraded to a warning.
    mipJsonPath = fullfile(packageDir, 'mip.json');
    deps = {};
    if exist(mipJsonPath, 'file')
        try
            mipConfig = mip.utils.read_package_json(packageDir);
            deps = mipConfig.dependencies;
            if ~iscell(deps)
                deps = {deps};
            end
        catch ME
            warning('mip:jsonParseError', ...
                    'Could not parse mip.json for package "%s": %s', ...
                    fqn, ME.message);
        end
    end

    if ~isempty(deps)
        fprintf('Loading dependencies for "%s": %s\n', ...
                fqn, strjoin(deps, ', '));
        for i = 1:length(deps)
            dep = deps{i};
            % Resolve dependency: same channel first, then core
            depFqn = mip.utils.resolve_dependency(dep, result.org, result.channel);
            if ~mip.utils.is_loaded(depFqn)
                loadSingle(depFqn, installIfMissing, false, channel, false, loadingStack);
            else
                fprintf('  Dependency "%s" is already loaded\n', depFqn);
            end
        end
    end

    % Look for load_package.m file
    loadFile = fullfile(packageDir, 'load_package.m');
    if ~exist(loadFile, 'file')
        error('mip:loadNotFound', ...
              'Package "%s" does not have a load_package.m file', fqn);
    end

    % Execute the load_package.m file. If it errors, the package is NOT
    % marked as loaded, so the user can fix the issue and retry. We do not
    % attempt to roll back any path or state changes that load_package.m
    % may have made before failing -- doing so reliably is not possible.
    originalDir = pwd;
    restoreDir = onCleanup(@() cd(originalDir));
    cd(packageDir);
    try
        run(loadFile);
    catch ME
        loadErr = MException('mip:loadError', ...
            'Error executing load_package.m for package "%s": %s', ...
            fqn, ME.message);
        loadErr = addCause(loadErr, ME);
        throw(loadErr);
    end
    clear restoreDir;
    fprintf('Loaded package "%s"\n', fqn);

    % Mark package as loaded
    mip.utils.key_value_append('MIP_LOADED_PACKAGES', fqn);

    % Track directly loaded packages separately
    if isDirect
        mip.utils.key_value_append('MIP_DIRECTLY_LOADED_PACKAGES', fqn);
    end

    % Mark package as sticky if requested
    if stickyPackage
        mip.utils.key_value_append('MIP_STICKY_PACKAGES', fqn);
        fprintf('Package "%s" is now sticky\n', fqn);
    end
end

function fqn = resolveToFqn(packageArg)
% Resolve a package argument to a fully qualified name.
% If already FQN, return as-is. If bare name, look up installed packages.

    result = mip.utils.parse_package_arg(packageArg);

    if result.is_fqn
        fqn = packageArg;
    else
        % Resolve bare name to installed FQN
        fqn = mip.utils.resolve_bare_name(result.name);
        if isempty(fqn)
            error('mip:packageNotFound', ...
                  'Package "%s" is not installed. Run "mip install %s" first.', ...
                  result.name, result.name);
        end
    end
end

