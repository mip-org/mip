function from_local(sourceDir, editable, noCompile, sourceType)
%FROM_LOCAL   Install a package from a local directory with mip.yaml.
%
% Non-channel packages live under a top-level source-type directory
% (no <owner>/<channel>). 'local' is used for directory and editable installs;
% 'fex' for File Exchange installs; 'web' for generic remote .zip installs.
%
% Args:
%   sourceDir  - Path to the directory containing mip.yaml
%   editable   - If true, create an editable install (no copy)
%   noCompile  - If true, skip compilation (editable installs only)
%   sourceType - Source type ('local', 'fex', or 'web'). Default: 'local'.

if nargin < 2
    editable = false;
end
if nargin < 3
    noCompile = false;
end
if nargin < 4
    sourceType = 'local';
end

validSourceTypes = {'local', 'fex', 'web'};
if ~ismember(sourceType, validSourceTypes)
    error('mip:install:invalidSourceType', ...
          'Invalid sourceType "%s". Must be one of: %s.', ...
          sourceType, strjoin(validSourceTypes, ', '));
end

% Resolve to absolute path
sourceDir = mip.paths.get_absolute_path(sourceDir);

% Read mip.yaml to get package name
mipConfig = mip.config.read_mip_yaml(sourceDir);
packageName = mipConfig.name;

if isempty(mipConfig.version)
    displayVersion = 'unspecified';
else
    displayVersion = mipConfig.version;
end
fprintf('Found package "%s" (version %s)\n', packageName, displayVersion);

fqn = [sourceType '/' packageName];

% Check if already installed. If an equivalent but differently-cased/
% separator-punctuated name is on disk, reject rather than silently skip:
% allowing the install would create a parallel directory for the same
% logical package.
existingName = mip.resolve.installed_dir(fqn);
if ~isempty(existingName) && ~strcmp(existingName, packageName)
    existingFqn = [sourceType '/' existingName];
    error('mip:install:equivalentAlreadyInstalled', ...
          ['Cannot install "%s": an equivalent package "%s" is already installed. ' ...
           'Package names are equivalent when they match after lowercasing and ' ...
           'treating "-" and "_" as the same character. Uninstall "%s" first.'], ...
          fqn, existingFqn, existingFqn);
end

pkgDir = mip.paths.get_package_dir(fqn);
if exist(pkgDir, 'dir')
    fprintf('Package "%s" is already installed. Uninstall first to reinstall.\n', fqn);
    return;
end

% Install any missing channel dependencies declared in mip.yaml, as
% remote installs do. They are installed transitively (not marked
% directly installed), so they can be pruned when no longer needed.
% Non-channel dependencies (local/fex/web) cannot be fetched from a
% channel, so a missing one is still an error.
installedMissingDeps = false;
if ~isempty(mipConfig.dependencies)
    fprintf('Dependencies: %s\n', strjoin(mipConfig.dependencies, ', '));
    missing = mip.dependency.find_missing(mipConfig.dependencies, fqn);
    nonChannel = missing(~startsWith(missing, 'gh/'));
    if ~isempty(nonChannel)
        error('mip:dependencyNotFound', ...
              'Dependency "%s" is not installed. Install it first.', ...
              mip.parse.display_fqn(nonChannel{1}));
    end
    if ~isempty(missing)
        missingDisplay = cellfun(@mip.parse.display_fqn, missing, 'UniformOutput', false);
        fprintf('Installing missing dependencies: %s\n', strjoin(missingDisplay, ', '));
        mip.install.from_repository(missing, '', false);
        installedMissingDeps = true;
    end
end

try
    if editable
        installEditable(sourceDir, mipConfig, pkgDir, fqn, noCompile);
    else
        installCopy(sourceDir, pkgDir, fqn);
    end
catch ME
    % Dependencies installed above are transitive; with their dependent
    % gone they are orphans, so prune them rather than leave them behind.
    if installedMissingDeps
        try
            mip.state.prune_unused_packages();
        catch pruneErr
            warning('mip:rollbackFailed', ...
                    'Rollback prune failed: %s', pruneErr.message);
        end
    end
    rethrow(ME);
end

% Mark as directly installed
mip.state.add_directly_installed(fqn);
fprintf('Successfully installed "%s"\n', fqn);
fprintf('\nTo use this package, run:\n');
fprintf('  mip load %s\n', mip.resolve.get_shortest_name(fqn));

% Warn if package exists in multiple channels
allInstalled = mip.resolve.find_all_installed_by_name(packageName);
if length(allInstalled) > 1
    fprintf('\nWarning: Package "%s" is installed from multiple channels:\n', packageName);
    for i = 1:length(allInstalled)
        fprintf('  - %s\n', mip.parse.display_fqn(allInstalled{i}));
    end
end

end


function installCopy(sourceDir, pkgDir, fqn)
% Non-editable install: prepare in temp dir, then move into place.
% This strips MEX binaries and compiles for the current architecture,
% matching the behavior of channel builds.

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

        % Store source_path in mip.json for update tracking
        mipJsonPath = fullfile(pkgDir, 'mip.json');
        jsonText = fileread(mipJsonPath);
        mipData = jsondecode(jsonText);
        mipData.source_path = sourceDir;
        fid = fopen(mipJsonPath, 'w');
        if fid == -1
            error('mip:fileError', 'Could not write to mip.json at %s', mipJsonPath);
        end
        fwrite(fid, jsonencode(mipData));
        fclose(fid);

        fprintf('Install complete.\n');

    catch ME
        % Clean up on failure (stagingDir if before movefile, pkgDir if after)
        if exist(stagingDir, 'dir')
            rmdir(stagingDir, 's');
        end
        if exist(pkgDir, 'dir')
            rmdir(pkgDir, 's');
        end
        rethrow(ME);
    end

end


function installEditable(sourceDir, mipConfig, pkgDir, fqn, noCompile)
% Editable install: create thin wrapper pointing to original source.
% Unlike installCopy, this does NOT strip MEX binaries or copy files.
% It DOES compile by default (unless --no-compile is used).

    fprintf('Installing "%s" in editable mode...\n', fqn);

    % Match the build and derive mip.json metadata. Paths are computed
    % relative to the source directory and stored in mip.json verbatim;
    % mip.load resolves them against source_path at load time
    % (source_path = sourceDir for editable installs).
    [effectiveArch, jsonOpts] = mip.build.resolve_metadata(sourceDir, mipConfig);

    % Create package directory
    parentDir = fileparts(pkgDir);
    if ~exist(parentDir, 'dir')
        mkdir(parentDir);
    end
    mkdir(pkgDir);

    % Create mip.json (a thin wrapper pointing to the original source)
    jsonOpts.editable = true;
    jsonOpts.source_path = sourceDir;
    mip.build.create_mip_json(pkgDir, mipConfig, effectiveArch, jsonOpts);

    fprintf('Editable install complete. Changes in %s will be reflected immediately.\n', sourceDir);

    % Compile unless --no-compile was specified
    if isfield(jsonOpts, 'compile_script')
        if noCompile
            fprintf('\nCompilation skipped (--no-compile).\n');
            fprintf('To compile later, run:\n');
            fprintf('  mip compile %s\n', mipConfig.name);
        else
            fprintf('\nCompiling...\n');
            mip.build.run_compile(sourceDir, jsonOpts.compile_script);
            fprintf('\nIf you edit files that require recompilation, run:\n');
            fprintf('  mip compile %s\n', mipConfig.name);
        end
    end

end
