function bundle(varargin)
%BUNDLE   Build a .mhl package file from a local directory with mip.yaml.
%
% Usage:
%   mip bundle /path/to/package
%   mip bundle /path/to/package --output /path/to/output
%   mip bundle /path/to/package --arch linux_x86_64
%
% Options:
%   --output <dir>   Output directory for the .mhl file (default: current dir)
%   --arch <arch>    Override architecture (default: auto-detect via mip.build.arch())
%
% The .mhl file is a ZIP archive containing:
%   mip.json
%   <package_name>/
%     [all package source files]
%
% The output filename follows the scheme: <name>-<version>-<architecture>.mhl

    if nargin < 1
        error('mip:bundle:noDirectory', ...
              'A directory path is required for bundle command.');
    end

    % Parse arguments
    [opts, positionals] = mip.parse.flags(varargin, struct('output', '', 'arch', ''));
    outputDir = opts.output;
    if isempty(outputDir)
        outputDir = pwd;
    end

    if length(positionals) > 1
        error('mip:bundle:unexpectedArg', 'Unexpected argument: %s', positionals{2});
    end
    if isempty(positionals)
        error('mip:bundle:noDirectory', ...
              'A directory path is required for bundle command.');
    end
    sourceDir = positionals{1};

    % Resolve source directory
    sourceDir = mip.paths.get_absolute_path(sourceDir);

    % Check for mip.yaml
    if ~exist(fullfile(sourceDir, 'mip.yaml'), 'file')
        error('mip:bundle:noMipYaml', ...
              'Directory "%s" does not contain a mip.yaml file.', sourceDir);
    end

    % Resolve output directory
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end
    outputDir = mip.paths.get_absolute_path(outputDir);

    % Prepare in a staging directory
    stagingDir = tempname;

    try
        % Prepare the package
        if isempty(opts.arch)
            mipConfig = mip.build.prepare_package(sourceDir, stagingDir);
        else
            mipConfig = mip.build.prepare_package(sourceDir, stagingDir, opts.arch);
        end

        % Bundle runtime-library dependencies of any MEX files in the
        % staged package, so the resulting .mhl depends only on system
        % libraries and libraries MATLAB resolves itself. No-op on
        % Windows (bundle_runtime_libs doesn't handle .mexw64 deps yet).
        pkgSubdir = fullfile(stagingDir, mipConfig.name);
        mexFiles = dir(fullfile(pkgSubdir, '**', '*.mex*'));
        mexFiles = mexFiles(~[mexFiles.isdir]);
        for i = 1:numel(mexFiles)
            mip.build.bundle_runtime_libs( ...
                fullfile(mexFiles(i).folder, mexFiles(i).name));
        end

        % Read mip.json to get the effective architecture and version
        % (mip.json's version may differ from mip.yaml's when a channel
        % build supplied a release-dir version override).
        mipJsonPath = fullfile(stagingDir, 'mip.json');
        mipJsonText = fileread(mipJsonPath);
        mipJson = jsondecode(mipJsonText);
        effectiveArch = mipJson.architecture;

        % Build output filename. Canonical package names may contain '-',
        % but the filename uses '-' as a field separator, so encode the
        % name with '_' in the filename.
        nameForFilename = strrep(mipConfig.name, '-', '_');
        mhlFilename = sprintf('%s-%s-%s.mhl', ...
            nameForFilename, mipJson.version, effectiveArch);
        mhlPath = fullfile(outputDir, mhlFilename);

        % Create .mhl (zip) from staging directory contents
        fprintf('Bundling %s...\n', mhlFilename);

        % MATLAB zip() auto-appends .zip, so zip to a temp name then rename
        zipBase = fullfile(outputDir, [mipConfig.name '_tmp_bundle']);
        zip(zipBase, '.', stagingDir);
        % zip() creates zipBase.zip
        movefile([zipBase '.zip'], mhlPath);

        % Also copy mip.json alongside the .mhl for index assembly
        mipJsonOutputPath = [mhlPath '.mip.json'];
        copyfile(mipJsonPath, mipJsonOutputPath);

        fprintf('Successfully created %s\n', mhlPath);
        fprintf('Metadata written to %s\n', mipJsonOutputPath);

    catch ME
        % Clean up staging dir on failure (best-effort: must not mask ME).
        removeStagingDir(stagingDir);
        rethrow(ME);
    end

    % Clean up staging dir
    removeStagingDir(stagingDir);

end

function removeStagingDir(stagingDir)
% Remove the bundle staging directory.
%
% On Windows a freshly written .mexw64 is briefly held by the OS file
% scanner that opens every newly written PE/DLL, and a held file can be
% neither deleted nor renamed (it is opened without FILE_SHARE_DELETE), so
% an immediate rmdir fails. The hold is transient, so retry for a few
% seconds to let the scanner release. If it is still held after that (e.g.
% a binary genuinely loaded into this MATLAB session), fall back to a
% warning and leave the uniquely named temp dir for the OS to reclaim --
% the .mhl is already written, so cleanup must not fail the bundle.
% Non-Windows rethrows immediately: a failed rmdir there is a real error.
    if ~exist(stagingDir, 'dir')
        return
    end
    maxAttempts = 3;
    for attempt = 1:maxAttempts
        try
            rmdir(stagingDir, 's');
            return
        catch rmErr
            if ~ispc
                rethrow(rmErr);
            end
            if attempt == maxAttempts
                warning('mip:bundle:stagingNotRemoved', ...
                        ['Could not remove staging dir "%s" after %d ' ...
                         'attempts (a freshly built binary is still held ' ...
                         'by another process); leaving it for the OS to ' ...
                         'reclaim: %s'], stagingDir, maxAttempts, ...
                        rmErr.message);
                return
            end
            pause(1);
        end
    end
end
