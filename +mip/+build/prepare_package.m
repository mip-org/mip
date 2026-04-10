function mipConfig = prepare_package(sourceDir, stagingDir, architecture)
%PREPARE_PACKAGE   Prepare a package for installation in a staging directory.
%
% Copies source into stagingDir/<package_name>/, strips mex binaries,
% generates load/unload scripts and mip.json, and runs compilation if needed.
%
% Args:
%   sourceDir    - Original source directory containing mip.yaml
%   stagingDir   - Temp directory to build the package layout in
%   architecture - (Optional) Architecture override. Default: mip.arch()
%
% Returns:
%   mipConfig - Parsed mip.yaml struct
%
% The resulting stagingDir layout:
%   stagingDir/
%     load_package.m
%     unload_package.m
%     mip.json
%     <package_name>/
%       [all source files]

if nargin < 3
    architecture = '';
end

% Read mip.yaml
mipConfig = mip.config.read_mip_yaml(sourceDir);
packageName = mipConfig.name;

fprintf('Preparing package "%s" (version %s)\n', packageName, ...
        num2str(mipConfig.version));

% Match build for current architecture
[buildEntry, effectiveArch] = mip.build.match_build(mipConfig, architecture);
fprintf('Matched build for architecture: %s\n', effectiveArch);

% Resolve build config (merge top-level defaults with build overrides)
resolvedConfig = mip.build.resolve_build_config(mipConfig, buildEntry);

% Create staging directory
if ~exist(stagingDir, 'dir')
    mkdir(stagingDir);
end

% Copy source into stagingDir/<package_name>/
pkgSubdir = fullfile(stagingDir, packageName);
fprintf('Copying source files...\n');
copyfile(sourceDir, pkgSubdir);

% Remove .git directory if present
gitDir = fullfile(pkgSubdir, '.git');
if exist(gitDir, 'dir')
    rmdir(gitDir, 's');
end

% Strip pre-existing mex binaries
numStripped = mip.build.strip_mex_binaries(pkgSubdir);
if numStripped > 0
    fprintf('Stripping pre-existing MEX binaries...\n');
end

% Compute addpaths relative to the source subdir
addpathsList = mip.build.compute_addpaths(pkgSubdir, resolvedConfig.addpaths);

% Prefix paths with package_name for the load/unload scripts
% (since scripts live in stagingDir, one level above the source)
prefixedPaths = cell(size(addpathsList));
for i = 1:length(addpathsList)
    if strcmp(addpathsList{i}, '.')
        prefixedPaths{i} = packageName;
    else
        prefixedPaths{i} = fullfile(packageName, addpathsList{i});
    end
end

% Generate load/unload scripts in stagingDir
fprintf('Generating load_package.m and unload_package.m...\n');
mip.build.create_path_scripts(stagingDir, prefixedPaths);

% Run compilation if specified
if isfield(resolvedConfig, 'compile_script') && ...
        ~isempty(resolvedConfig.compile_script)
    fprintf('Compiling...\n');
    mip.build.run_compile(pkgSubdir, resolvedConfig.compile_script);
end

% Create mip.json
fprintf('Creating mip.json...\n');
jsonOpts = struct();
sourceHashFile = fullfile(pkgSubdir, '.source_hash');
if exist(sourceHashFile, 'file')
    fid = fopen(sourceHashFile, 'r');
    jsonOpts.source_hash = strtrim(fread(fid, '*char')');
    fclose(fid);
    delete(sourceHashFile);
end
commitHashFile = fullfile(pkgSubdir, '.commit_hash');
if exist(commitHashFile, 'file')
    fid = fopen(commitHashFile, 'r');
    jsonOpts.commit_hash = strtrim(fread(fid, '*char')');
    fclose(fid);
    delete(commitHashFile);
end
if isfield(resolvedConfig, 'test_script') && ~isempty(resolvedConfig.test_script)
    jsonOpts.test_script = resolvedConfig.test_script;
end
if isfield(resolvedConfig, 'compile_script') && ~isempty(resolvedConfig.compile_script)
    jsonOpts.compile_script = resolvedConfig.compile_script;
end
mip.build.create_mip_json(stagingDir, mipConfig, resolvedConfig, effectiveArch, jsonOpts);

end
