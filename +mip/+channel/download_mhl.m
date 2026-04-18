function localPath = download_mhl(source, destDir, expectedSha256)
%DOWNLOAD_MHL   Download a .mhl package file from URL or copy from local path.
%
% Args:
%   source          - URL (http:// or https://) or local file path
%   destDir         - Destination directory for the downloaded file
%   expectedSha256  - (Optional) Expected hex SHA-256 of the file (case-insensitive).
%                     If provided and nonempty, the downloaded/copied file is
%                     verified against this digest. On mismatch the local
%                     copy is deleted and an error is raised. If the JVM is
%                     unavailable (e.g. numbl), verification is skipped.
%
% Returns:
%   localPath - Path to the downloaded/copied file
%
% Example:
%   filepath = mip.channel.download_mhl('https://example.com/pkg.mhl', tempdir);
%   filepath = mip.channel.download_mhl('/path/to/local/pkg.mhl', tempdir);
%   filepath = mip.channel.download_mhl(url, tempdir, pkgInfo.mhl_sha256);

if nargin < 3
    expectedSha256 = '';
end

% Ensure destination directory exists
if ~exist(destDir, 'dir')
    mkdir(destDir);
end

source = char(source);

% Check if source is a URL or local file
isURL = startsWith(source, {'http://', 'https://'});

if isURL
    % Download from URL using websave
    % Extract filename from URL
    [~, filename, ext] = fileparts(source);
    % Handle URLs with query parameters
    if contains(ext, '?')
        ext = extractBefore(ext, '?');
    end
    if isempty(ext)
        ext = '.mhl'; % Default extension for packages
    end
    localPath = fullfile(destDir, [filename ext]);

    try
        fprintf('Downloading from %s...\n', source);
        % Note: websave() does not support progress callbacks or custom headers
        % This is a limitation of MATLAB's HTTP capabilities
        websave(localPath, source, weboptions('Timeout', 60));
        fprintf('Download complete.\n');
    catch ME
        error('mip:downloadFailed', ...
              'Failed to download file from %s: %s', source, ME.message);
    end
else
    % Local file - verify it exists and copy
    if ~exist(source, 'file')
        error('mip:fileNotFound', 'Local file not found: %s', source);
    end
    [~, filename, ext] = fileparts(source);
    localPath = fullfile(destDir, [filename ext]);

    try
        copyfile(source, localPath);
    catch ME
        error('mip:copyFailed', ...
              'Failed to copy file from %s: %s', source, ME.message);
    end
end

if ~isempty(expectedSha256)
    actual = mip.channel.sha256(localPath);
    if isempty(actual)
        % JVM unavailable (e.g. numbl) — skip verification.
        return
    end
    if ~strcmpi(actual, expectedSha256)
        if exist(localPath, 'file')
            delete(localPath);
        end
        error('mip:digestMismatch', ...
              ['SHA-256 mismatch for %s\n' ...
               '  expected: %s\n' ...
               '  actual:   %s'], source, expectedSha256, actual);
    end
end

end
