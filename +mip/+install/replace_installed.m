function wasLoaded = replace_installed(fqn, pkgDir, latestInfo)
%REPLACE_INSTALLED   Replace an installed package with a channel version.
%
% The shared replace machinery for `mip update` (remote packages) and
% `mip install <pkg>@<version>` (version switches). Download-first: the
% new version is downloaded and extracted to a staging directory before
% the installed copy is touched, so a failed download leaves the package
% installed and loaded. The old directory is then moved to a backup, the
% staged version swapped in, and the backup removed; if the swap fails
% the backup is restored. Atomic per package.
%
% Args:
%   fqn        - Canonical FQN of the installed package
%   pkgDir     - Its installed directory
%   latestInfo - Channel-index variant struct (mhl_url, mhl_sha256, ...)
%
% Returns:
%   wasLoaded - true if the package was loaded (it is unloaded here;
%               the caller decides when to reload).

    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    expectedSha = '';
    if isfield(latestInfo, 'mhl_sha256')
        expectedSha = latestInfo.mhl_sha256;
    end
    mhlPath = mip.channel.download_mhl(latestInfo.mhl_url, tempDir, expectedSha);
    stagingDir = fullfile(tempDir, 'staging');
    mip.channel.extract_mhl(mhlPath, stagingDir);

    % Download succeeded — now it is safe to unload and swap. The self
    % identity gh/mip-org/core/mip is always "loaded" as session state,
    % but when this path runs for it the copy being replaced belongs to a
    % root mip does not run from (own-root replacements go through
    % mip.self.hot_swap), so there is nothing on the path to unload — and
    % mip.unload would refuse the identity anyway.
    wasLoaded = mip.state.is_loaded(fqn) && ~strcmp(fqn, 'gh/mip-org/core/mip');
    if wasLoaded
        mip.unload(fqn);
    end

    backupDir = mip.paths.backup_dir(pkgDir);
    try
        movefile(stagingDir, pkgDir);
    catch ME
        mip.paths.restore_dir(backupDir, pkgDir);
        rethrow(ME);
    end
    % The backup is the replaced old package; remove it robustly in case
    % a binary it shipped was loaded before the replace.
    mip.paths.remove_dir(backupDir);
end

function rmTempDir(d)
    if exist(d, 'dir')
        rmdir(d, 's');
    end
end
