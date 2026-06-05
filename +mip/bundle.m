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

    % Opportunistically remove staging dirs that an earlier Windows bundle
    % could only move aside (a MEX built in that session was still loaded).
    purgeBundleTrash();

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
% On Windows a native binary built during bundling can end up loaded in
% this MATLAB session (or held by the OS file scanner just after it is
% written), and a held .mexw64 cannot be deleted, so rmdir fails. Windows
% still allows renaming such a file, so move the staging dir into a trash
% area on the same volume -- a metadata-only rename that succeeds even while
% the binary is held -- and let purgeBundleTrash() delete it on a later
% bundle once nothing has it open. The .mhl is already written by this
% point, so cleanup never fails the bundle. Non-Windows does a plain rmdir.
    if ~exist(stagingDir, 'dir')
        return
    end
    try
        rmdir(stagingDir, 's');
        return
    catch rmErr
        if ~ispc
            rethrow(rmErr);
        end
    end

    trashDir = bundleTrashRoot();
    if ~exist(trashDir, 'dir')
        mkdir(trashDir);
    end
    % tempname(trashDir) is on the same volume as stagingDir (both under
    % tempdir), so the move is a rename, not a copy+delete that would trip
    % over the held file.
    [moved, msg] = movefile(stagingDir, tempname(trashDir), 'f');
    if ~moved
        warning('mip:bundle:stagingNotRemoved', ...
                'Could not remove or move aside staging dir "%s": %s', ...
                stagingDir, msg);
    end
end

function purgeBundleTrash()
% Best-effort deletion of staging dirs left by a previous Windows bundle
% that could only be moved aside (a binary built then was still held).
% Entries still held stay locked and are left for a later run.
    trashDir = bundleTrashRoot();
    if ~exist(trashDir, 'dir')
        return
    end
    entries = dir(trashDir);
    for i = 1:numel(entries)
        nm = entries(i).name;
        if strcmp(nm, '.') || strcmp(nm, '..')
            continue
        end
        target = fullfile(trashDir, nm);
        try
            if entries(i).isdir
                rmdir(target, 's');
            else
                delete(target);
            end
        catch
            % Still held; leave it for a later run.
        end
    end
end

function d = bundleTrashRoot()
% Trash area for staging dirs that could not be removed in-session. Kept
% under tempdir so a move from a tempname() staging dir is a same-volume
% rename (cross-volume movefile would copy the held file and then fail to
% delete the source).
    d = fullfile(tempdir, '.mip-trash');
end
