function localPath = download_mhl(source, destDir)
%DOWNLOAD_MHL   Download a .mhl package file from URL or copy from local path.
%
% Args:
%   source - URL (http:// or https://) or local file path
%   destDir - Destination directory for the downloaded file
%
% Returns:
%   localPath - Path to the downloaded/copied file
%
% Example:
%   filepath = mip.channel.download_mhl('https://example.com/pkg.mhl', tempdir);
%   filepath = mip.channel.download_mhl('/path/to/local/pkg.mhl', tempdir);

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

end
