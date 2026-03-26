function list()
%LIST   List all installed mip packages.
%
% Usage:
%   mip.list()
%
% Displays all currently installed packages with their versions.
% Loaded packages are shown in a separate section at the top.
% An asterisk (*) indicates a directly loaded package.
% [sticky] indicates a sticky package.
%
% Example:
%   mip.list()
%   % Output:
%   % === Loaded Packages ===
%   %  * chebfun (5.7.0) [sticky]
%   %    dependency1 (1.0.0)
%   %
%   % === Other Installed Packages ===
%   %    package1 (1.2.3)

packagesDir = mip.utils.get_packages_dir();

if ~exist(packagesDir, 'dir')
    fprintf('No packages installed yet\n');
    return
end

% Get list of package directories
dirContents = dir(packagesDir);
packages = {};

for i = 1:length(dirContents)
    if dirContents(i).isdir && ~startsWith(dirContents(i).name, '.')
        packages = [packages, {dirContents(i).name}]; %#ok<AGROW>
    end
end

if isempty(packages)
    fprintf('No packages installed yet\n');
    return
end

% Get loaded and sticky packages
MIP_LOADED_PACKAGES          = mip.utils.key_value_get('MIP_LOADED_PACKAGES');
MIP_DIRECTLY_LOADED_PACKAGES = mip.utils.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
MIP_STICKY_PACKAGES          = mip.utils.key_value_get('MIP_STICKY_PACKAGES');

% Categorize packages into loaded and not loaded
loadedPackages = {};
notLoadedPackages = {};

for i = 1:length(packages)
    pkgName = packages{i};
    if ismember(pkgName, MIP_LOADED_PACKAGES)
        loadedPackages{end+1} = pkgName; %#ok<AGROW>
    else
        notLoadedPackages{end+1} = pkgName; %#ok<AGROW>
    end
end

% Sort both lists alphabetically
loadedPackages = sort(loadedPackages);
notLoadedPackages = sort(notLoadedPackages);

% Display loaded packages section
if isempty(loadedPackages)
    fprintf('No packages are currently loaded. Use "mip load <package>" to load one.\n\n');
else
    fprintf('=== Loaded Packages ===\n');
    for i = 1:length(loadedPackages)
        pkgName = loadedPackages{i};
        pkgDir = fullfile(packagesDir, pkgName);

        % Try to read version from mip.json
        version = 'unknown';
        try
            pkgInfo = mip.utils.read_package_json(pkgDir);
            if isfield(pkgInfo, 'version')
                version = pkgInfo.version;
            end
        catch
            % Ignore errors reading mip.json
        end

        % Check if direct and sticky
        isDirect = ismember(pkgName, MIP_DIRECTLY_LOADED_PACKAGES);
        isSticky = ismember(pkgName, MIP_STICKY_PACKAGES);
        
        % Build the display line with proper indentation
        if isDirect
            prefix = ' *';
        else
            prefix = '  ';
        end
        
        pkgLine = sprintf('%s %s (%s)', prefix, pkgName, version);

        % Add channel indicator
        pkgChannel = mip.utils.get_package_channel(pkgName);
        if ~isempty(pkgChannel) && ~strcmp(pkgChannel, 'core')
            pkgLine = sprintf('%s [%s]', pkgLine, pkgChannel);
        end

        % Add sticky indicator
        if isSticky
            pkgLine = sprintf('%s [sticky]', pkgLine);
        end
        
        fprintf('%s\n', pkgLine);
    end
    fprintf('\n');
end

% Display not loaded packages section
if ~isempty(notLoadedPackages)
    fprintf('=== Other Installed Packages ===\n');
    for i = 1:length(notLoadedPackages)
        pkgName = notLoadedPackages{i};
        pkgDir = fullfile(packagesDir, pkgName);

        % Try to read version from mip.json
        version = 'unknown';
        try
            pkgInfo = mip.utils.read_package_json(pkgDir);
            if isfield(pkgInfo, 'version')
                version = pkgInfo.version;
            end
        catch
            % Ignore errors reading mip.json
        end

        pkgLine = sprintf('   %s (%s)', pkgName, version);

        % Add channel indicator
        pkgChannel = mip.utils.get_package_channel(pkgName);
        if ~isempty(pkgChannel) && ~strcmp(pkgChannel, 'core')
            pkgLine = sprintf('%s [%s]', pkgLine, pkgChannel);
        end

        fprintf('%s\n', pkgLine);
    end
end

end
