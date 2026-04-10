function list(varargin)
%LIST   List all installed mip packages.
%
% Usage:
%   mip list              - List packages (default: reverse load order)
%   mip list --sort-by-name  - List packages sorted alphabetically by name
%
% Columns: name, fqn, version. Asterisk (*) marks directly loaded packages.
% Editable packages show their source location.

packagesDir = mip.paths.get_packages_dir();

if ~exist(packagesDir, 'dir')
    fprintf('No packages installed yet\n');
    return
end

% Parse flags
sortAlpha = false;
for i = 1:length(varargin)
    if strcmp(varargin{i}, '--sort-by-name')
        sortAlpha = true;
    end
end

% Get all installed packages as FQNs
allPackages = mip.state.list_installed_packages();

if isempty(allPackages)
    fprintf('No packages installed yet\n');
    return
end

% Get loaded and sticky packages
MIP_LOADED_PACKAGES          = mip.state.key_value_get('MIP_LOADED_PACKAGES');
MIP_DIRECTLY_LOADED_PACKAGES = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
MIP_STICKY_PACKAGES          = mip.state.key_value_get('MIP_STICKY_PACKAGES');

% Build info for each package
n = length(allPackages);
names = cell(1, n);
versions = cell(1, n);
editablePaths = cell(1, n);
loaded = false(1, n);
direct = false(1, n);
sticky = false(1, n);
editable = false(1, n);

for i = 1:n
    fqn = allPackages{i};
    result = mip.parse.parse_package_arg(fqn);
    names{i} = result.name;
    pkgDir = mip.paths.get_package_dir(result.org, result.channel, result.name);

    versions{i} = 'unknown';
    editablePaths{i} = '';
    try
        pkgInfo = mip.config.read_package_json(pkgDir);
        if isfield(pkgInfo, 'version')
            versions{i} = pkgInfo.version;
        end
        if isfield(pkgInfo, 'editable') && pkgInfo.editable && isfield(pkgInfo, 'source_path')
            editable(i) = true;
            editablePaths{i} = pkgInfo.source_path;
        end
    catch
    end

    loaded(i) = ismember(fqn, MIP_LOADED_PACKAGES);
    direct(i) = ismember(fqn, MIP_DIRECTLY_LOADED_PACKAGES);
    sticky(i) = ismember(fqn, MIP_STICKY_PACKAGES);
end

loadedIdx = find(loaded);
notLoadedIdx = find(~loaded);

% Sort loaded packages
if sortAlpha
    [~, si] = sort(lower(names(loadedIdx)));
    loadedIdx = loadedIdx(si);
else
    % Reverse load order (most recent first = MATLAB path precedence)
    loadOrder = zeros(size(loadedIdx));
    for i = 1:length(loadedIdx)
        pos = find(strcmp(allPackages{loadedIdx(i)}, MIP_LOADED_PACKAGES));
        if ~isempty(pos)
            loadOrder(i) = pos;
        end
    end
    [~, si] = sort(loadOrder, 'descend');
    loadedIdx = loadedIdx(si);
end

% Sort non-loaded packages alphabetically by name
[~, si] = sort(lower(names(notLoadedIdx)));
notLoadedIdx = notLoadedIdx(si);

% Display loaded packages section
if isempty(loadedIdx)
    fprintf('No packages are currently loaded. Use "mip load <package>" to load one.\n\n');
else
    fprintf('=== Loaded Packages ===\n');
    print_packages(loadedIdx, names, allPackages, versions, direct, sticky, editable, editablePaths);
    fprintf('\n');
end

% Display not-loaded packages section
if ~isempty(notLoadedIdx)
    fprintf('=== Other Installed Packages ===\n');
    print_packages(notLoadedIdx, names, allPackages, versions, direct, sticky, editable, editablePaths);
end

end


function print_packages(idx, names, fqns, versions, direct, sticky, editable, editablePaths)
    % Compute column widths for this section
    maxNameLen = 0;
    maxFqnLen = 0;
    for i = idx
        maxNameLen = max(maxNameLen, length(names{i}));
        maxFqnLen = max(maxFqnLen, length(fqns{i}));
    end

    for i = idx
        if direct(i)
            prefix = ' *';
        else
            prefix = '  ';
        end

        line = sprintf('%s %-*s  %-*s  %s', prefix, maxNameLen, names{i}, ...
            maxFqnLen, fqns{i}, versions{i});

        if sticky(i)
            line = sprintf('%s [sticky]', line);
        end

        if editable(i)
            line = sprintf('%s [editable: %s]', line, editablePaths{i});
        end

        fprintf('%s\n', line);
    end
end
