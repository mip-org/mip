function bundle(varargin)
%BUNDLE   Build a .mhl package file from a local directory with mip.yaml.
%
% Usage:
%   mip.bundle('/path/to/package')
%   mip.bundle('/path/to/package', '--output', '/path/to/output')
%   mip.bundle('/path/to/package', '--arch', 'linux_x86_64')
%
% Options:
%   --output <dir>   Output directory for the .mhl file (default: current dir)
%   --arch <arch>    Override architecture (default: auto-detect via mip.arch())
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
    sourceDir = '';
    outputDir = pwd;
    architecture = '';

    i = 1;
    while i <= length(varargin)
        arg = varargin{i};
        if ischar(arg) && strcmp(arg, '--output')
            if i + 1 > length(varargin)
                error('mip:bundle:missingOutput', '--output requires a directory argument');
            end
            outputDir = varargin{i + 1};
            i = i + 2;
        elseif ischar(arg) && strcmp(arg, '--arch')
            if i + 1 > length(varargin)
                error('mip:bundle:missingArch', '--arch requires an architecture argument');
            end
            architecture = varargin{i + 1};
            i = i + 2;
        elseif isempty(sourceDir)
            sourceDir = arg;
            i = i + 1;
        else
            error('mip:bundle:unexpectedArg', 'Unexpected argument: %s', arg);
        end
    end

    if isempty(sourceDir)
        error('mip:bundle:noDirectory', ...
              'A directory path is required for bundle command.');
    end

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
        if isempty(architecture)
            mipConfig = mip.build.prepare_package(sourceDir, stagingDir);
        else
            mipConfig = mip.build.prepare_package(sourceDir, stagingDir, architecture);
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
            nameForFilename, num2str(mipJson.version), effectiveArch);
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
        % Clean up staging dir on failure
        if exist(stagingDir, 'dir')
            rmdir(stagingDir, 's');
        end
        rethrow(ME);
    end

    % Clean up staging dir
    if exist(stagingDir, 'dir')
        rmdir(stagingDir, 's');
    end

end
