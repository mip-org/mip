function load(packageArg, varargin)
%LOAD   Load a mip package into the MATLAB path.
%
% Usage:
%   mip.load('packageName')
%   mip.load('packageName', '--sticky')
%   mip.load('org/channel/packageName')
%
% Accepts both bare package names and fully qualified names (org/channel/package).
% For bare names, resolution priority is:
%   1. mip-org/core
%   2. First alphabetically by org/channel
%
% Use '--sticky' to mark the package as sticky, which prevents it from
% being unloaded with 'mip unload --all'.

    % Resolve the FQN for this package
    fqn = resolveToFqn(packageArg);

    % mip-org/core/mip is always loaded — nothing to do
    if strcmp(fqn, 'mip-org/core/mip')
        fprintf('Package "mip" is always loaded\n');
        return
    end

    % Check for --sticky flag in arguments
    stickyPackage = false;
    remainingArgs = {};
    for i = 1:length(varargin)
        if ischar(varargin{i}) && strcmp(varargin{i}, '--sticky')
            stickyPackage = true;
        else
            remainingArgs{end+1} = varargin{i}; %#ok<*AGROW>
        end
    end

    % Parse optional arguments for internal use
    p = inputParser;
    addParameter(p, 'loadingStack', {}, @iscell);
    addParameter(p, 'isDirect', true, @islogical);
    parse(p, remainingArgs{:});
    loadingStack = p.Results.loadingStack;
    isDirect = p.Results.isDirect;

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

    % Check for mip.json and process dependencies
    mipJsonPath = fullfile(packageDir, 'mip.json');
    if exist(mipJsonPath, 'file')
        try
            fid = fopen(mipJsonPath, 'r');
            jsonText = fread(fid, '*char')';
            fclose(fid);
            mipConfig = jsondecode(jsonText);

            % Load dependencies first
            if isfield(mipConfig, 'dependencies') && ~isempty(mipConfig.dependencies)
                deps = mipConfig.dependencies;
                if ~iscell(deps)
                    deps = {deps};
                end
                fprintf('Loading dependencies for "%s": %s\n', ...
                        fqn, strjoin(deps, ', '));
                for i = 1:length(deps)
                    dep = deps{i};
                    % Resolve dependency: same channel first, then core
                    depFqn = resolveDependency(dep, result.org, result.channel);
                    if ~mip.utils.is_loaded(depFqn)
                        mip.load(depFqn, 'loadingStack', loadingStack, 'isDirect', false);
                    else
                        fprintf('  Dependency "%s" is already loaded\n', depFqn);
                    end
                end
            end
        catch ME
            warning('mip:jsonParseError', ...
                    'Could not parse mip.json for package "%s": %s', ...
                    fqn, ME.message);
        end
    end

    % Look for load_package.m file
    loadFile = fullfile(packageDir, 'load_package.m');
    if ~exist(loadFile, 'file')
        error('mip:loadNotFound', ...
              'Package "%s" does not have a load_package.m file', fqn);
    end

    % Execute the load_package.m file
    originalDir = pwd;
    cd(packageDir);
    try
        run(loadFile);
        fprintf('Loaded package "%s"\n', fqn);
    catch ME
        warning('mip:loadError', ...
                'Error executing load_package.m for package "%s": %s', ...
                fqn, ME.message);
    end
    cd(originalDir);

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

function depFqn = resolveDependency(depName, contextOrg, contextChannel)
% Resolve a dependency name. If it's a FQN, use as-is.
% If bare, try same channel first, then mip-org/core.

    result = mip.utils.parse_package_arg(depName);

    if result.is_fqn
        depFqn = depName;
        return
    end

    % Try same channel first
    sameChannelDir = mip.utils.get_package_dir(contextOrg, contextChannel, result.name);
    if exist(sameChannelDir, 'dir')
        depFqn = mip.utils.make_fqn(contextOrg, contextChannel, result.name);
        return
    end

    % Try mip-org/core
    coreDir = mip.utils.get_package_dir('mip-org', 'core', result.name);
    if exist(coreDir, 'dir')
        depFqn = mip.utils.make_fqn('mip-org', 'core', result.name);
        return
    end

    % Fall back to general resolution
    depFqn = mip.utils.resolve_bare_name(result.name);
    if isempty(depFqn)
        error('mip:dependencyNotFound', ...
              'Dependency "%s" is not installed.', result.name);
    end
end
