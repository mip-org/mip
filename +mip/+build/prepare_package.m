function mipConfig = prepare_package(sourceDir, stagingDir, architecture)
%PREPARE_PACKAGE   Prepare a package for installation in a staging directory.
%
% Copies source into stagingDir/<package_name>/, strips mex binaries,
% generates load/unload scripts and mip.json, and runs compilation if needed.
%
% Args:
%   sourceDir    - Original source directory containing mip.yaml
%   stagingDir   - Temp directory to build the package layout in
%   architecture - (Optional) Architecture override. Default: mip.build.arch()
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

% If the channel build supplied a .release_version override, use it for
% the status message and mip.json. Falls back to mip.yaml's version.
effectiveVersion = num2str(mipConfig.version);
sourceReleaseVersionFile = fullfile(sourceDir, '.release_version');
if exist(sourceReleaseVersionFile, 'file')
    fid = fopen(sourceReleaseVersionFile, 'r');
    effectiveVersion = strtrim(fread(fid, '*char')');
    fclose(fid);
end

fprintf('Preparing package "%s" (version %s)\n', packageName, ...
        effectiveVersion);

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

% Strip pre-existing compiled binaries (vendored/stale MEX, libs, executables)
numStripped = mip.build.strip_prebuilt_binaries(pkgSubdir);
if numStripped > 0
    fprintf('Stripping pre-existing compiled binaries...\n');
end

% Match the build and derive mip.json metadata from the staged copy
[effectiveArch, jsonOpts] = mip.build.resolve_metadata(pkgSubdir, mipConfig, architecture);
fprintf('Matched build for architecture: %s\n', effectiveArch);

% Run compilation if specified
if isfield(jsonOpts, 'compile_script')
    fprintf('Compiling...\n');
    mip.build.run_compile(pkgSubdir, jsonOpts.compile_script);
end

% Create mip.json
fprintf('Creating mip.json...\n');
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
% The channel build drops .release_version next to .source_hash when the
% release-directory name should override mip.yaml's version (e.g. a branch
% name like "main" for a blank/numeric mip.yaml version).
releaseVersionFile = fullfile(pkgSubdir, '.release_version');
if exist(releaseVersionFile, 'file')
    jsonOpts.version = effectiveVersion;
    delete(releaseVersionFile);
end
mip.build.create_mip_json(stagingDir, mipConfig, effectiveArch, jsonOpts);

end
