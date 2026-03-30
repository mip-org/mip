function list()
%LIST   List all installed mip packages.
%
% Usage:
%   mip.list()
%
% Displays all currently installed packages with their versions.
% Packages are shown by their fully qualified name (org/channel/package).
% Loaded packages are shown in a separate section at the top.
% An asterisk (*) indicates a directly loaded package.
% [sticky] indicates a sticky package.

packagesDir = mip.utils.get_packages_dir();

if ~exist(packagesDir, 'dir')
    fprintf('No packages installed yet\n');
    return
end

% Get all installed packages as FQNs
allPackages = mip.utils.list_installed_packages();

if isempty(allPackages)
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

for i = 1:length(allPackages)
    fqn = allPackages{i};
    if ismember(fqn, MIP_LOADED_PACKAGES)
        loadedPackages{end+1} = fqn; %#ok<AGROW>
    else
        notLoadedPackages{end+1} = fqn; %#ok<AGROW>
    end
end

% Display loaded packages section
if isempty(loadedPackages)
    fprintf('No packages are currently loaded. Use "mip load <package>" to load one.\n\n');
else
    fprintf('=== Loaded Packages ===\n');
    for i = 1:length(loadedPackages)
        fqn = loadedPackages{i};
        result = mip.utils.parse_package_arg(fqn);
        pkgDir = mip.utils.get_package_dir(result.org, result.channel, result.name);

        % Try to read version from mip.json
        version = 'unknown';
        try
            pkgInfo = mip.utils.read_package_json(pkgDir);
            if isfield(pkgInfo, 'version')
                version = pkgInfo.version;
            end
        catch
        end

        % Check if direct and sticky
        isDirect = ismember(fqn, MIP_DIRECTLY_LOADED_PACKAGES);
        isSticky = ismember(fqn, MIP_STICKY_PACKAGES);

        if isDirect
            prefix = ' *';
        else
            prefix = '  ';
        end

        pkgLine = sprintf('%s %s (%s)', prefix, fqn, version);

        if isSticky
            pkgLine = sprintf('%s [sticky]', pkgLine);
        end

        % Check if editable
        try
            if isfield(pkgInfo, 'editable') && pkgInfo.editable
                pkgLine = sprintf('%s [editable]', pkgLine);
            end
        catch
        end

        fprintf('%s\n', pkgLine);
    end
    fprintf('\n');
end

% Display not loaded packages section
if ~isempty(notLoadedPackages)
    fprintf('=== Other Installed Packages ===\n');
    for i = 1:length(notLoadedPackages)
        fqn = notLoadedPackages{i};
        result = mip.utils.parse_package_arg(fqn);
        pkgDir = mip.utils.get_package_dir(result.org, result.channel, result.name);

        % Try to read version from mip.json
        version = 'unknown';
        try
            pkgInfo = mip.utils.read_package_json(pkgDir);
            if isfield(pkgInfo, 'version')
                version = pkgInfo.version;
            end
        catch
        end

        pkgLine = sprintf('   %s (%s)', fqn, version);

        % Check if editable
        try
            if isfield(pkgInfo, 'editable') && pkgInfo.editable
                pkgLine = sprintf('%s [editable]', pkgLine);
            end
        catch
        end

        fprintf('%s\n', pkgLine);
    end
end

end
