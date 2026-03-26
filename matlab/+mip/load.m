function load(packageName, varargin)
%LOAD   Load a mip package into the MATLAB path.
%
% Usage:
%   mip.load('packageName')
%   mip.load('packageName', '--sticky')
%
% This function loads the specified package from ~/.mip/packages by
% executing its load_package.m file. Use '--sticky' to mark the package as sticky,
% which prevents it from being unloaded with 'mip unload --all'.

    % mip is always loaded — nothing to do
    if strcmp(packageName, 'mip')
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
    if ismember(packageName, loadingStack)
        cycle = strjoin([loadingStack, {packageName}], ' -> ');
        error('mip:circularDependency', ...
              'Circular dependency detected: %s', cycle);
    end

    % Add to loading stack for circular dependency detection
    loadingStack = [loadingStack, {packageName}];

    % Get the mip packages directory
    packagesDir = mip.utils.get_packages_dir();
    packageDir = fullfile(packagesDir, packageName);

    % Check if package exists
    if ~exist(packageDir, 'dir')
        error('mip:packageNotFound', ...
              'Package "%s" is not installed. Run "mip install %s" first.', ...
              packageName, packageName);
    end

    % Check if package is already loaded
    if mip.utils.is_loaded(packageName)
        % If this is a direct load and the package was previously
        % loaded as a dependency, mark it as direct now
        if isDirect && ~mip.utils.is_directly_loaded(packageName)
            mip.utils.key_value_append('MIP_DIRECTLY_LOADED_PACKAGES', packageName);
            fprintf('Package "%s" is already loaded (now marked as direct)\n', packageName);
        else
            fprintf('Package "%s" is already loaded\n', packageName);
        end
        % If --sticky was specified, add to sticky packages
        if stickyPackage
            if ~mip.utils.is_sticky(packageName)
                mip.utils.key_value_append('MIP_STICKY_PACKAGES', packageName);
                fprintf('Package "%s" is now sticky\n', packageName);
            end
        end
        return
    end

    % Check for mip.json and process dependencies
    mipJsonPath = fullfile(packageDir, 'mip.json');
    if exist(mipJsonPath, 'file')
        try
            % Read and parse mip.json
            fid = fopen(mipJsonPath, 'r');
            jsonText = fread(fid, '*char')';
            fclose(fid);
            mipConfig = jsondecode(jsonText);

            % Load dependencies first
            if isfield(mipConfig, 'dependencies') && ~isempty(mipConfig.dependencies)
                fprintf('Loading dependencies for "%s": %s\n', ...
                        packageName, strjoin(mipConfig.dependencies, ', '));
                for i = 1:length(mipConfig.dependencies)
                    dep = mipConfig.dependencies{i};
                    if ~mip.utils.is_loaded(dep)
                        mip.load(dep, 'loadingStack', loadingStack, 'isDirect', false);
                    else
                        fprintf('  Dependency "%s" is already loaded\n', dep);
                    end
                end
            end
        catch ME
            warning('mip:jsonParseError', ...
                    'Could not parse mip.json for package "%s": %s', ...
                    packageName, ME.message);
        end
    end

    % Look for load_package.m file
    loadFile = fullfile(packageDir, 'load_package.m');
    if ~exist(loadFile, 'file')
        error('mip:loadNotFound', ...
              'Package "%s" does not have a load_package.m file', packageName);
    end

    % Execute the load_package.m file
    originalDir = pwd;
    cd(packageDir);
    try
        run(loadFile);
        fprintf('Loaded package "%s"\n', packageName);
    catch ME
        warning('mip:loadError', ...
                'Error executing load_package.m for package "%s": %s', ...
                packageName, ME.message);
    end
    cd(originalDir);

    % Mark package as loaded
    mip.utils.key_value_append('MIP_LOADED_PACKAGES', packageName);

    % Track directly loaded packages separately
    if isDirect
        mip.utils.key_value_append('MIP_DIRECTLY_LOADED_PACKAGES', packageName);
    end

    % Mark package as sticky if requested
    if stickyPackage
        mip.utils.key_value_append('MIP_STICKY_PACKAGES', packageName);
        fprintf('Package "%s" is now sticky\n', packageName);
    end
end
