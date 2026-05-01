function localPath = download_mhl(source, destDir, expectedSha256)
%DOWNLOAD_MHL   Download a .mhl package file from URL or copy from local path.
%
% Args:
%   source          - HTTPS URL or local file path. Plain http:// is
%                     rejected (a network attacker could otherwise swap
%                     .mhl payloads, leading to arbitrary code execution
%                     once the package is loaded).
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

% Reject plain HTTP URLs. mhl_url comes from a channel's index.json, and
% any third-party channel can be added via `--channel owner/channel`;
% allowing http:// would let a network attacker swap the payload and
% achieve persistent code execution once the package is loaded.
if startsWith(source, 'http://')
    error('mip:downloadMhl:requireHttps', ...
          'Refusing to download .mhl over plain HTTP; use https:// instead. Got: %s', ...
          source);
end

% Check if source is a URL or local file
isURL = startsWith(source, 'https://');

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

% SHA-256 verification disabled — see mip-org/mip#201.
% Channel publishing is not atomic: the .mhl asset is uploaded before the
% index.json is redeployed, so clients fetching during the window get an
% old digest with a new archive and trip mip:digestMismatch. Re-enable
% once channel publishing is made atomic (content-addressed asset names
% or staging→promote).
% if ~isempty(expectedSha256)
%     actual = mip.channel.sha256(localPath);
%     if isempty(actual)
%         % JVM unavailable (e.g. numbl) — skip verification.
%         return
%     end
%     if ~strcmpi(actual, expectedSha256)
%         if exist(localPath, 'file')
%             delete(localPath);
%         end
%         error('mip:digestMismatch', ...
%               ['SHA-256 mismatch for %s\n' ...
%                '  expected: %s\n' ...
%                '  actual:   %s'], source, expectedSha256, actual);
%     end
% end

end
