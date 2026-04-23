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
%     mip.json
%     <package_name>/
%       [all source files]
%
% Paths to add to the MATLAB path at load time are stored in mip.json
% under the "paths" field, relative to the package source directory.

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

% Compute resolved path lists relative to the source subdir
pathsList = mip.build.compute_addpaths(pkgSubdir, resolvedConfig.paths);
extraPaths = struct();
for key = fieldnames(resolvedConfig.extra_paths)'
    extraPaths.(key{1}) = mip.build.compute_addpaths( ...
        pkgSubdir, resolvedConfig.extra_paths.(key{1}));
end

% Run compilation if specified
if isfield(resolvedConfig, 'compile_script') && ...
        ~isempty(resolvedConfig.compile_script)
    fprintf('Compiling...\n');
    mip.build.run_compile(pkgSubdir, resolvedConfig.compile_script);
end

% Create mip.json
fprintf('Creating mip.json...\n');
jsonOpts = struct();
jsonOpts.paths = pathsList;
if ~isempty(fieldnames(extraPaths))
    jsonOpts.extra_paths = extraPaths;
end
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
mip.build.create_mip_json(stagingDir, mipConfig, effectiveArch, jsonOpts);

end
