function install_local(sourceDir, editable)
%INSTALL_LOCAL   Install a package from a local directory with mip.yaml.
%
% Args:
%   sourceDir - Path to the directory containing mip.yaml
%   editable  - If true, create an editable install (no copy, no compile)

if nargin < 2
    editable = false;
end

% Resolve to absolute path
w = what(sourceDir);
if isempty(w)
    error('mip:install:notADirectory', '"%s" is not a directory.', sourceDir);
end
sourceDir = w.path;

% Read mip.yaml to get package name
mipConfig = mip.utils.read_mip_yaml(sourceDir);
packageName = mipConfig.name;

fprintf('Found package "%s" (version %s)\n', packageName, ...
        num2str(mipConfig.version));

% Use local/local as the org/channel for local installs
org = 'local';
channelName = 'local';
fqn = mip.utils.make_fqn(org, channelName, packageName);

% Check if already installed
pkgDir = mip.utils.get_package_dir(org, channelName, packageName);
if exist(pkgDir, 'dir')
    fprintf('Package "%s" is already installed. Uninstall first to reinstall.\n', fqn);
    return;
end

% Check dependencies are installed
if ~isempty(mipConfig.dependencies)
    fprintf('Dependencies: %s\n', strjoin(mipConfig.dependencies, ', '));
    for i = 1:length(mipConfig.dependencies)
        dep = mipConfig.dependencies{i};
        depFqn = mip.utils.resolve_bare_name(dep);
        if isempty(depFqn)
            error('mip:dependencyNotFound', ...
                  'Dependency "%s" is not installed. Install it first.', dep);
        end
    end
end

if editable
    installEditable(sourceDir, mipConfig, pkgDir, fqn);
else
    installCopy(sourceDir, pkgDir, fqn);
end

% Mark as directly installed
mip.utils.add_directly_installed(fqn);
fprintf('Successfully installed "%s"\n', fqn);

% Warn if package exists in multiple channels
allInstalled = mip.utils.find_all_installed_by_name(packageName);
if length(allInstalled) > 1
    fprintf('\nWarning: Package "%s" is installed from multiple channels:\n', packageName);
    for i = 1:length(allInstalled)
        fprintf('  - %s\n', allInstalled{i});
    end
end

end


function installCopy(sourceDir, pkgDir, fqn)
% Non-editable install: prepare in temp dir, then move into place.

    stagingDir = tempname;

    try
        fprintf('Installing "%s"...\n', fqn);
        mip.build.prepare_package(sourceDir, stagingDir);

        % Create parent directories if needed
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end

        % Move staging dir to final location
        movefile(stagingDir, pkgDir);
        fprintf('Install complete.\n');

    catch ME
        % Clean up staging dir on failure
        if exist(stagingDir, 'dir')
            rmdir(stagingDir, 's');
        end
        rethrow(ME);
    end

end


function installEditable(sourceDir, mipConfig, pkgDir, fqn)
% Editable install: create thin wrapper pointing to original source.

    fprintf('Installing "%s" in editable mode...\n', fqn);

    % Match build and resolve config to determine addpaths
    [buildEntry, effectiveArch] = mip.build.match_build(mipConfig);
    resolvedConfig = mip.build.resolve_build_config(mipConfig, buildEntry);

    % Compute addpaths relative to the source directory
    addpathsList = mip.build.compute_addpaths(sourceDir, resolvedConfig.addpaths);

    % Convert to absolute paths for editable install
    absolutePaths = cell(size(addpathsList));
    for i = 1:length(addpathsList)
        if strcmp(addpathsList{i}, '.')
            absolutePaths{i} = sourceDir;
        else
            absolutePaths{i} = fullfile(sourceDir, addpathsList{i});
        end
    end

    % Create package directory
    parentDir = fileparts(pkgDir);
    if ~exist(parentDir, 'dir')
        mkdir(parentDir);
    end
    mkdir(pkgDir);

    % Generate load/unload scripts with absolute paths
    scriptOpts = struct('absolute', true);
    mip.build.create_load_script(pkgDir, absolutePaths, scriptOpts);
    mip.build.create_unload_script(pkgDir, absolutePaths, scriptOpts);

    % Create mip.json
    jsonOpts = struct('editable', true, 'source_path', sourceDir);
    mip.build.create_mip_json(pkgDir, mipConfig, resolvedConfig, effectiveArch, jsonOpts);

    fprintf('Editable install complete. Changes in %s will be reflected immediately.\n', sourceDir);

    % Print compile hint if a compile script is specified
    if isfield(resolvedConfig, 'compile_script') && ...
            ~isempty(resolvedConfig.compile_script)
        fprintf('\nNote: This is an editable install. No compilation was performed.\n');
        fprintf('To compile, run in MATLAB:\n');
        fprintf('  cd(''%s''); run(''%s'');\n', sourceDir, resolvedConfig.compile_script);
    end

end
