function hot_swap(pkgDir, oldPkgInfo, latestInfo)
%HOT_SWAP   Replace the running mip package's files in place with a new build.
%
%   mip.self.hot_swap(PKGDIR, OLDPKGINFO, LATESTINFO)
%
% mip cannot be swapped through the normal unload/reinstall path: it is the
% code that is currently executing, so the moment its directory is moved or
% its path entries are removed, the mip.* helpers become unreachable. This
% function performs the swap "hot" — while mip is live — by doing everything
% that needs mip.* BEFORE the old copy is torn down:
%
%   1. Download and extract the new build (LATESTINFO) into a staging dir.
%   2. Resolve the old path entries (from OLDPKGINFO) and the new ones (read
%      from the staged mip.json) to absolute paths, up front.
%   3. rmpath the old entries, delete PKGDIR, move staging into PKGDIR, then
%      addpath the new entries.
%
% After step 2, nothing here calls any mip.* function or local helper, so
% tearing down the old copy (which contains this very file) cannot break the
% swap — the running invocation continues from memory. Callers (mip.install,
% mip.update) decide LATESTINFO and print the user-facing messages; this
% function is purely the mechanism.
%
% Args:
%   pkgDir      - installed location of mip
%                 (<root>/packages/gh/mip-org/core/mip)
%   oldPkgInfo  - the currently-installed mip.json struct (for its "paths")
%   latestInfo  - channel index entry for the target build; must carry
%                 mhl_url, and optionally mhl_sha256

    tempDir = tempname;
    mkdir(tempDir);
    try
        expectedSha = '';
        if isfield(latestInfo, 'mhl_sha256')
            expectedSha = latestInfo.mhl_sha256;
        end
        mhlPath = mip.channel.download_mhl(latestInfo.mhl_url, tempDir, expectedSha);
        stagingDir = fullfile(tempDir, 'staging');
        mip.channel.extract_mhl(mhlPath, stagingDir);

        % Resolve all path lists BEFORE touching the installed mip. Once we
        % rmpath+rmdir the old mip, the mip.* helpers are no longer
        % reachable, so everything we need from them must be computed now.
        oldPathsToRemove = {};
        if isfield(oldPkgInfo, 'paths')
            oldSrcDir = mip.paths.get_source_dir(pkgDir, oldPkgInfo);
            oldPathsToRemove = resolvePathList(oldSrcDir, oldPkgInfo.paths);
        end

        % New package info is read from staging. After movefile, the staging
        % layout ends up at pkgDir, so source paths resolve under
        % pkgDir/<name>/.
        newPkgInfo = mip.config.read_package_json(stagingDir);
        newPathsToAdd = {};
        if isfield(newPkgInfo, 'paths')
            newSrcDir = fullfile(pkgDir, newPkgInfo.name);
            newPathsToAdd = resolvePathList(newSrcDir, newPkgInfo.paths);
        end

        % Unload the currently installed mip by rmpath'ing the entries
        % declared in the old mip.json "paths" field.
        oldWarn = warning('off', 'MATLAB:rmpath:DirNotFound');
        for k = 1:length(oldPathsToRemove)
            rmpath(oldPathsToRemove{k});
        end
        warning(oldWarn);
        rmdir(pkgDir, 's');
        movefile(stagingDir, pkgDir);

        % Reload mip by addpath'ing the new entries (these now point into
        % the just-moved pkgDir).
        for k = 1:length(newPathsToAdd)
            addpath(newPathsToAdd{k});
        end
    catch ME
        if exist(tempDir, 'dir')
            rmdir(tempDir, 's');
        end
        rethrow(ME);
    end

    if exist(tempDir, 'dir')
        rmdir(tempDir, 's');
    end
end

function out = resolvePathList(srcDir, relPaths)
% Resolve each entry in relPaths (relative to srcDir) to an absolute path.
    out = cell(1, length(relPaths));
    for i = 1:length(relPaths)
        if strcmp(relPaths{i}, '.')
            out{i} = srcDir;
        else
            out{i} = fullfile(srcDir, relPaths{i});
        end
    end
end
