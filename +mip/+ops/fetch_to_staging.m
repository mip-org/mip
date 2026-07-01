function stagingDir = fetch_to_staging(packageInfo, tempDir)
%FETCH_TO_STAGING   Download a package's .mhl and extract it for install.
%
% Downloads packageInfo.mhl_url (verifying mhl_sha256 when present) into
% tempDir and extracts it to a staging subdirectory. The caller owns
% tempDir and its cleanup; the returned staging directory is ready to be
% moved into place with mip.ops.install_from_staging.
%
% Args:
%   packageInfo - Channel index entry; must carry mhl_url, and optionally
%                 mhl_sha256.
%   tempDir     - Existing temporary directory to download and extract in.
%
% Returns:
%   stagingDir - Directory containing the extracted package contents.

    expectedSha = '';
    if isfield(packageInfo, 'mhl_sha256')
        expectedSha = packageInfo.mhl_sha256;
    end
    mhlPath = mip.channel.download_mhl(packageInfo.mhl_url, tempDir, expectedSha);
    stagingDir = fullfile(tempDir, 'staging');
    mip.channel.extract_mhl(mhlPath, stagingDir);
end
