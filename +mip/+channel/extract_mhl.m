function extractDir = extract_mhl(mhlPath, destDir)
%EXTRACT_MHL   Extract a .mhl package file (zip format).
%
% Args:
%   mhlPath - Path to the .mhl file
%   destDir - Destination directory for extraction
%
% Returns:
%   extractDir - Path to the extraction directory
%
% Example:
%   extractDir = mip.channel.extract_mhl('/path/to/package.mhl', '/dest/dir');

% Verify .mhl file exists
if ~exist(mhlPath, 'file')
    error('mip:mhlNotFound', '.mhl file not found: %s', mhlPath);
end

% Validate all archive entry names BEFORE extracting, so a malicious
% archive cannot write files outside destDir. Rejects entries with
% ".." escapes, absolute paths, drive letters, or null bytes, and
% rejects symlink entries whose target (resolved relative to the
% link's own directory) would escape destDir. Errors with
% mip:pathTraversal if any entry is unsafe.
mip.channel.assert_mhl_safe(mhlPath);

% Ensure destination directory exists
if ~exist(destDir, 'dir')
    mkdir(destDir);
end

try
    fprintf('Extracting package...\n');
    extractedFiles = unzip(mhlPath, destDir);

    if isempty(extractedFiles)
        error('mip:extractFailed', 'No files extracted from .mhl package');
    end

    % Verify mip.json exists in extracted files
    mipJsonPath = fullfile(destDir, 'mip.json');
    if ~exist(mipJsonPath, 'file')
        error('mip:invalidPackage', ...
              'Package is missing mip.json file. This is not a valid mip package.');
    end

    extractDir = destDir;

catch ME
    % Clean up on failure
    if exist(destDir, 'dir')
        rmdir(destDir, 's');
    end

    if strcmp(ME.identifier, 'mip:invalidPackage') || ...
       strcmp(ME.identifier, 'mip:extractFailed')
        rethrow(ME);
    else
        error('mip:extractFailed', ...
              'Failed to extract .mhl file: %s', ME.message);
    end
end

end
