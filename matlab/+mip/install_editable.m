function install_editable(varargin)
%INSTALL_EDITABLE   Install a package in editable (development) mode.
%
% Usage:
%   mip.install_editable('/path/to/prepare/dir')
%   mip.install_editable('/path/to/prepare/dir', '--src-path', '/custom/src')
%   mip.install_editable('/path/to/prepare/dir', '--channel', 'dev')
%
% Installs a package from a prepare.yaml directory in editable mode. The
% source repository is cloned and the MATLAB path is configured to point
% directly into the source tree. This allows live editing of package files
% during development.
%
% The package is installed under local/editable/<name> in the mip packages
% directory. Dependencies are installed normally from the channel.
%
% Options:
%   --src-path <path>   Custom location for source clone (default: ~/.mip/src/<name>)
%   --channel <name>    Channel for installing dependencies (default: core)

    if nargin < 1
        error('mip:installEditable:noPath', ...
            'Path to prepare.yaml directory is required.\nUsage: mip install -e /path/to/prepare/dir');
    end

    % Parse arguments
    [prepareDir, srcPathOverride, channel] = parseArgs(varargin);

    % Validate prepare.yaml exists
    yamlPath = fullfile(prepareDir, 'prepare.yaml');
    if ~exist(yamlPath, 'file')
        error('mip:installEditable:noPrepareYaml', ...
            'No prepare.yaml found in: %s', prepareDir);
    end

    % Parse the prepare.yaml
    fprintf('Reading prepare.yaml from: %s\n', prepareDir);
    config = mip.utils.parse_yaml(yamlPath);

    % Extract package metadata
    packageName = config.name;
    packageVersion = config.version;
    if isnumeric(packageVersion)
        packageVersion = num2str(packageVersion);
    end

    fprintf('Package: %s (version: %s)\n', packageName, packageVersion);

    % Check if already installed as editable
    pkgDir = mip.utils.get_package_dir('local', 'editable', packageName);
    if exist(pkgDir, 'dir')
        fprintf('Package "%s" is already installed as editable.\n', packageName);
        fprintf('To reinstall, first run: mip uninstall local/editable/%s\n', packageName);
        return
    end

    % Check if installed normally (warn but don't block)
    existingFqn = mip.utils.resolve_bare_name(packageName);
    if ~isempty(existingFqn)
        fprintf('Warning: "%s" is already installed as %s\n', packageName, existingFqn);
        fprintf('The editable version (local/editable/%s) will take priority when loading.\n\n', packageName);
    end

    % Determine source path
    if isempty(srcPathOverride)
        srcPath = fullfile(mip.root(), 'src', packageName);
    else
        srcPath = srcPathOverride;
    end

    % Get prepare entries and addpaths from defaults
    if isfield(config, 'defaults')
        defaults = config.defaults;
    else
        error('mip:installEditable:noDefaults', ...
            'prepare.yaml must have a "defaults" section');
    end

    if ~isfield(defaults, 'prepare')
        error('mip:installEditable:noPrepare', ...
            'prepare.yaml defaults must have a "prepare" section');
    end

    if ~isfield(defaults, 'addpaths')
        error('mip:installEditable:noAddpaths', ...
            'prepare.yaml defaults must have an "addpaths" section');
    end

    % Normalize prepare entries to a cell array
    prepareEntries = normalizePrepareEntries(defaults.prepare);

    % Separate build-only from regular sources
    sources = {};
    buildOnlySources = {};
    for i = 1:length(prepareEntries)
        entry = prepareEntries{i};
        if isfield(entry, 'build_only') && entry.build_only
            buildOnlySources{end+1} = entry; %#ok<AGROW>
        else
            sources{end+1} = entry; %#ok<AGROW>
        end
    end

    if isempty(sources)
        error('mip:installEditable:noSources', ...
            'No non-build-only sources found in prepare.yaml');
    end

    % For editable installs, we only support a single primary source
    if length(sources) > 1
        error('mip:installEditable:multipleSources', ...
            'Editable install currently supports only one primary source (found %d)', ...
            length(sources));
    end

    source = sources{1};

    % Clone the source repository
    cloneSource(source, srcPath);

    % Build the destination-to-source-path mapping
    destMap = buildDestMap(source, srcPath);

    % Compute resolved addpaths (absolute paths into source tree)
    addpathEntries = normalizeAddpaths(defaults.addpaths);
    resolvedPaths = resolveAddpaths(addpathEntries, destMap, srcPath);

    % Create the package directory
    if ~exist(pkgDir, 'dir')
        mkdir(pkgDir);
    end

    % Generate load_package.m
    generateLoadScript(pkgDir, resolvedPaths);
    fprintf('Generated load_package.m\n');

    % Generate unload_package.m
    generateUnloadScript(pkgDir, resolvedPaths);
    fprintf('Generated unload_package.m\n');

    % Create mip.json
    createMipJson(pkgDir, config, srcPath, prepareDir);
    fprintf('Created mip.json\n');

    % Mark as directly installed
    fqn = mip.utils.make_fqn('local', 'editable', packageName);
    mip.utils.add_directly_installed(fqn);

    fprintf('\nEditable package "%s" installed at: %s\n', packageName, pkgDir);
    fprintf('Source tree at: %s\n', srcPath);

    % Install dependencies
    deps = {};
    if isfield(config, 'dependencies')
        deps = config.dependencies;
        if ischar(deps)
            deps = {deps};
        elseif ~iscell(deps)
            if isempty(deps)
                deps = {};
            else
                deps = cellstr(deps);
            end
        end
    end

    if ~isempty(deps)
        fprintf('\nInstalling dependencies: %s\n', strjoin(deps, ', '));
        if isempty(channel)
            channel = 'core';
        end
        mip.install('--channel', channel, deps{:});
    end

    % Print warnings
    printWarnings(config, source, buildOnlySources);

    fprintf('\nDone. Use "mip load %s" to load the package.\n', packageName);
end

%% Argument parsing

function [prepareDir, srcPath, channel] = parseArgs(args)
    prepareDir = '';
    srcPath = '';
    channel = '';

    i = 1;
    while i <= length(args)
        arg = args{i};
        if strcmp(arg, '--src-path')
            if i >= length(args)
                error('mip:installEditable:missingSrcPath', ...
                    '--src-path requires a path argument');
            end
            srcPath = args{i+1};
            i = i + 2;
        elseif strcmp(arg, '--channel')
            if i >= length(args)
                error('mip:installEditable:missingChannel', ...
                    '--channel requires a channel argument');
            end
            channel = args{i+1};
            i = i + 2;
        elseif isempty(prepareDir)
            prepareDir = arg;
            % Resolve to absolute path
            if ~startsWith(prepareDir, filesep)
                prepareDir = fullfile(pwd, prepareDir);
            end
            i = i + 1;
        else
            error('mip:installEditable:unexpectedArg', ...
                'Unexpected argument: %s', arg);
        end
    end

    if isempty(prepareDir)
        error('mip:installEditable:noPath', ...
            'Path to prepare.yaml directory is required.');
    end
end

%% Prepare entry normalization

function entries = normalizePrepareEntries(prepare)
% Normalize prepare field to a cell array of entries.
% prepare can be:
%   - a struct (single entry with clone_git/download_zip at top level)
%   - a cell array of structs (multiple entries)
%   - a struct array (multiple entries from jsondecode)

    if iscell(prepare)
        entries = prepare;
    elseif isstruct(prepare) && length(prepare) > 1
        % struct array
        entries = cell(1, length(prepare));
        for i = 1:length(prepare)
            entries{i} = prepare(i);
        end
    elseif isstruct(prepare) && length(prepare) == 1
        % Could be a single entry or a struct with clone_git directly
        if isfield(prepare, 'clone_git') || isfield(prepare, 'download_zip')
            entries = {prepare};
        else
            entries = {prepare};
        end
    else
        error('mip:installEditable:invalidPrepare', ...
            'Could not parse prepare entries from prepare.yaml');
    end
end

%% Source cloning

function cloneSource(source, srcPath)
% Clone the source repository to srcPath

    if exist(srcPath, 'dir')
        fprintf('Source directory already exists: %s\n', srcPath);
        fprintf('Using existing source. To re-clone, delete this directory and run again.\n');
        return
    end

    if isfield(source, 'clone_git')
        cloneGit = source.clone_git;
        url = cloneGit.url;

        % Build clone command
        cmd = sprintf('git clone');
        if isfield(cloneGit, 'branch')
            cmd = sprintf('%s --branch %s', cmd, cloneGit.branch);
        end
        cmd = sprintf('%s "%s" "%s"', cmd, url, srcPath);

        fprintf('Cloning source repository...\n');
        fprintf('  %s\n', cmd);
        [status, output] = system(cmd);
        if status ~= 0
            error('mip:installEditable:cloneFailed', ...
                'Failed to clone repository:\n%s', output);
        end
        fprintf('Source cloned to: %s\n', srcPath);

    elseif isfield(source, 'download_zip')
        error('mip:installEditable:downloadZipNotSupported', ...
            ['Editable installs are not supported for download_zip sources.\n' ...
             'Editable mode is designed for git-based development workflows.']);
    else
        error('mip:installEditable:unknownSourceType', ...
            'Unknown source type in prepare.yaml (expected clone_git)');
    end
end

%% Destination mapping

function destMap = buildDestMap(source, srcPath)
% Build a map from destination name to actual source path.
% For editable installs, we clone the full repo, so subdirectory
% references need to be remapped.
%
% Returns a containers.Map: destination_name -> absolute_source_path

    destMap = containers.Map('KeyType', 'char', 'ValueType', 'char');

    if isfield(source, 'clone_git')
        cloneGit = source.clone_git;
        dest = cloneGit.destination;

        if isfield(cloneGit, 'subdirectory')
            % The normal flow extracts just this subdirectory and names it dest.
            % For editable, the full repo is at srcPath, so dest maps to srcPath/subdirectory.
            actualPath = fullfile(srcPath, cloneGit.subdirectory);
        else
            % No subdirectory extraction — dest maps to the repo root
            actualPath = srcPath;
        end

        destMap(dest) = actualPath;
    end
end

%% Addpath normalization and resolution

function entries = normalizeAddpaths(addpaths)
% Normalize addpaths to a cell array of structs with at least a 'path' field.

    if isstruct(addpaths)
        entries = cell(1, length(addpaths));
        for i = 1:length(addpaths)
            entries{i} = addpaths(i);
        end
    elseif iscell(addpaths)
        entries = addpaths;
    else
        error('mip:installEditable:invalidAddpaths', ...
            'Could not parse addpaths from prepare.yaml');
    end
end

function resolved = resolveAddpaths(addpathEntries, destMap, srcPath)
% Resolve addpath entries to absolute paths in the source tree.
%
% For each addpath entry:
%   1. Find which destination prefix matches the path
%   2. Replace the destination prefix with the actual source path
%   3. If recursive, walk the directory tree

    resolved = {};
    destinations = destMap.keys();

    for i = 1:length(addpathEntries)
        entry = addpathEntries{i};

        % Get the path string
        if isstruct(entry)
            pathStr = entry.path;
        elseif ischar(entry)
            pathStr = entry;
        else
            continue
        end

        % Find matching destination prefix and remap
        remappedBase = remapPath(pathStr, destMap, destinations, srcPath);

        % Check for recursive flag
        isRecursive = isstruct(entry) && isfield(entry, 'recursive') && entry.recursive;

        if isRecursive
            excludeList = {};
            if isfield(entry, 'exclude')
                excludeList = entry.exclude;
                if ischar(excludeList)
                    excludeList = {excludeList};
                elseif ~iscell(excludeList)
                    excludeList = cellstr(excludeList);
                end
            end

            % Walk directory tree for recursive paths
            subPaths = computeRecursivePaths(remappedBase, excludeList);
            resolved = [resolved, subPaths]; %#ok<AGROW>
        else
            resolved{end+1} = remappedBase; %#ok<AGROW>
        end
    end
end

function remapped = remapPath(pathStr, destMap, destinations, srcPath)
% Remap a path by replacing destination prefix with actual source path.

    for i = 1:length(destinations)
        dest = destinations{i};
        if strcmp(pathStr, dest)
            remapped = destMap(dest);
            return
        elseif startsWith(pathStr, [dest '/']) || startsWith(pathStr, [dest filesep])
            remainder = pathStr(length(dest)+2:end);
            remapped = fullfile(destMap(dest), remainder);
            return
        end
    end

    % No destination match — treat as relative to srcPath
    remapped = fullfile(srcPath, pathStr);
end

function paths = computeRecursivePaths(basePath, excludeList)
% Walk directory tree and collect all directories containing .m files.
% Respects the exclude list.

    paths = {};
    paths = walkDir(basePath, basePath, excludeList, paths);
    paths = sort(paths);
end

function paths = walkDir(currentDir, basePath, excludeList, paths)
    % Check for .m files in current directory
    mFiles = dir(fullfile(currentDir, '*.m'));
    if ~isempty(mFiles)
        paths{end+1} = currentDir;
    end

    % Recurse into subdirectories
    entries = dir(currentDir);
    entries = entries([entries.isdir]);
    for i = 1:length(entries)
        name = entries(i).name;
        if startsWith(name, '.')
            continue
        end
        if ismember(name, excludeList)
            continue
        end
        paths = walkDir(fullfile(currentDir, name), basePath, excludeList, paths);
    end
end

%% Script generation

function generateLoadScript(pkgDir, resolvedPaths)
% Generate load_package.m that adds source tree paths to MATLAB path.

    fid = fopen(fullfile(pkgDir, 'load_package.m'), 'w');
    fprintf(fid, 'function load_package()\n');
    fprintf(fid, '%%%% Load editable package by adding source tree paths to MATLAB path.\n');
    for i = 1:length(resolvedPaths)
        fprintf(fid, '    addpath(''%s'');\n', strrep(resolvedPaths{i}, '''', ''''''));
    end
    fprintf(fid, 'end\n');
    fclose(fid);
end

function generateUnloadScript(pkgDir, resolvedPaths)
% Generate unload_package.m that removes source tree paths from MATLAB path.

    fid = fopen(fullfile(pkgDir, 'unload_package.m'), 'w');
    fprintf(fid, 'function unload_package()\n');
    fprintf(fid, '%%%% Unload editable package by removing source tree paths from MATLAB path.\n');
    for i = 1:length(resolvedPaths)
        fprintf(fid, '    rmpath(''%s'');\n', strrep(resolvedPaths{i}, '''', ''''''));
    end
    fprintf(fid, 'end\n');
    fclose(fid);
end

%% mip.json creation

function createMipJson(pkgDir, config, srcPath, prepareDir)
% Create mip.json for the editable package.

    mipJson = struct();
    mipJson.name = config.name;
    mipJson.version = config.version;
    if isnumeric(mipJson.version)
        mipJson.version = num2str(mipJson.version);
    end

    if isfield(config, 'description')
        mipJson.description = config.description;
    else
        mipJson.description = '';
    end

    if isfield(config, 'dependencies')
        deps = config.dependencies;
        if ischar(deps)
            deps = {deps};
        elseif ~iscell(deps) && ~isempty(deps)
            deps = cellstr(deps);
        elseif isempty(deps)
            deps = {};
        end
        mipJson.dependencies = deps;
    else
        mipJson.dependencies = {};
    end

    if isfield(config, 'homepage')
        mipJson.homepage = config.homepage;
    end
    if isfield(config, 'repository')
        mipJson.repository = config.repository;
    end
    if isfield(config, 'license')
        mipJson.license = config.license;
    end

    % Editable-specific fields
    mipJson.editable = true;
    mipJson.source_path = srcPath;
    mipJson.prepare_yaml_path = prepareDir;

    % Write JSON
    jsonText = jsonencode(mipJson);
    % Pretty-print with newlines after commas for readability
    jsonText = strrep(jsonText, ',"', sprintf(',\n"'));
    jsonText = strrep(jsonText, '{', sprintf('{\n'));
    jsonText = strrep(jsonText, '}', sprintf('\n}'));

    fid = fopen(fullfile(pkgDir, 'mip.json'), 'w');
    fprintf(fid, '%s\n', jsonText);
    fclose(fid);
end

%% Warnings

function printWarnings(config, source, buildOnlySources)
% Print warnings about things the user needs to handle manually.

    warnings = {};

    % Check for remove_dirs
    if isfield(source, 'clone_git') && isfield(source.clone_git, 'remove_dirs')
        removeDirs = source.clone_git.remove_dirs;
        if ischar(removeDirs)
            removeDirs = {removeDirs};
        elseif ~iscell(removeDirs)
            removeDirs = cellstr(removeDirs);
        end
        warnings{end+1} = sprintf( ...
            ['Note: The prepare.yaml specifies remove_dirs: %s\n' ...
             '  These directories are NOT removed from your source tree,\n' ...
             '  but they are not added to the MATLAB path.'], ...
            strjoin(removeDirs, ', '));
    end

    % Check for compile_script in any build
    if isfield(config, 'builds')
        builds = config.builds;
        if isstruct(builds)
            builds_cell = cell(1, length(builds));
            for i = 1:length(builds)
                builds_cell{i} = builds(i);
            end
        elseif iscell(builds)
            builds_cell = builds;
        else
            builds_cell = {};
        end

        for i = 1:length(builds_cell)
            b = builds_cell{i};
            if isfield(b, 'compile_script')
                warnings{end+1} = sprintf( ...
                    ['Note: This package requires MATLAB compilation (compile_script: %s).\n' ...
                     '  You will need to run this manually in the source directory.\n' ...
                     '  cd to the source directory and run the compile script.'], ...
                    b.compile_script); %#ok<AGROW>
                break
            end
            if isfield(b, 'build_script')
                warnings{end+1} = sprintf( ...
                    ['Note: This package requires a build step (build_script: %s).\n' ...
                     '  You will need to run this manually.'], ...
                    b.build_script); %#ok<AGROW>
                break
            end
        end
    end

    % Check for build-only sources
    if ~isempty(buildOnlySources)
        names = {};
        for i = 1:length(buildOnlySources)
            s = buildOnlySources{i};
            if isfield(s, 'clone_git') && isfield(s.clone_git, 'destination')
                names{end+1} = s.clone_git.destination; %#ok<AGROW>
            end
        end
        if ~isempty(names)
            warnings{end+1} = sprintf( ...
                ['Note: The prepare.yaml has build-only sources (%s) which are\n' ...
                 '  used during compilation but not included in the final package.\n' ...
                 '  If you need to compile, you may need to clone these separately.'], ...
                strjoin(names, ', '));
        end
    end

    % Print warnings
    if ~isempty(warnings)
        fprintf('\n');
        for i = 1:length(warnings)
            fprintf('%s\n\n', warnings{i});
        end
    end
end
