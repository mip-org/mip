function installedFqn = from_mhl(mhlSource, channel)
%FROM_MHL   Install a package from a local .mhl file or URL.
%
% When no --channel is given, the package lands under the 'mhl/' source
% type (e.g. 'mhl/chebfun'), so a .mhl from an arbitrary path or URL
% cannot masquerade as a member of the default core channel. Passing
% --channel <owner>/<channel> opts in to gh-channel placement.
%
% Args:
%   mhlSource - Path or URL of the .mhl archive
%   channel   - Channel spec from --channel, or '' for 'mhl/' placement
%
% Returns:
%   installedFqn - FQN of the installed package, or '' if it was already
%                  installed.

    installedFqn = '';
    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    useGhChannel = ~isempty(channel);
    if useGhChannel
        [channelOwner, channelName] = mip.parse.parse_channel_spec(channel);
    end

    try
        mhlPath = mip.channel.download_mhl(mhlSource, tempDir);
        extractDir = fullfile(tempDir, 'extracted');
        mip.channel.extract_mhl(mhlPath, extractDir);

        pkgInfo = mip.config.read_package_json(extractDir);
        packageName = pkgInfo.name;
        if useGhChannel
            fqn = mip.parse.make_fqn(channelOwner, channelName, packageName);
        else
            fqn = mip.parse.make_mhl_fqn(packageName);
        end

        existingName = mip.resolve.installed_dir(fqn);
        if ~isempty(existingName) && ~strcmp(existingName, packageName)
            if useGhChannel
                existingFqn = mip.parse.make_fqn(channelOwner, channelName, existingName);
            else
                existingFqn = mip.parse.make_mhl_fqn(existingName);
            end
            error('mip:install:equivalentAlreadyInstalled', ...
                  ['Cannot install "%s": an equivalent package "%s" is already installed. ' ...
                   'Package names are equivalent when they match after lowercasing and ' ...
                   'treating "-" and "_" as the same character. Uninstall "%s" first.'], ...
                  mip.parse.display_fqn(fqn), mip.parse.display_fqn(existingFqn), ...
                  mip.parse.display_fqn(existingFqn));
        end

        pkgDir = mip.paths.get_package_dir(fqn);
        if exist(pkgDir, 'dir')
            fprintf('Package "%s" is already installed\n', mip.parse.display_fqn(fqn));
            mip.state.add_directly_installed(fqn);
            return
        end

        if ~isempty(pkgInfo.dependencies)
            fprintf('\nPackage "%s" has dependencies: %s\n', ...
                    mip.parse.display_fqn(fqn), strjoin(pkgInfo.dependencies, ', '));
            fprintf('Installing dependencies from remote repository...\n');
            mip.install.from_repository(pkgInfo.dependencies, channel, false);
        end

        fprintf('\nInstalling "%s"...\n', mip.parse.display_fqn(fqn));
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end
        movefile(extractDir, pkgDir);
        fprintf('Successfully installed "%s"\n', mip.parse.display_fqn(fqn));
        mip.state.add_directly_installed(fqn);
        installedFqn = fqn;

    catch ME
        fprintf('\nInstall failed; rolling back any orphaned dependencies...\n');
        try
            mip.state.prune_unused_packages();
        catch pruneErr
            warning('mip:rollbackFailed', ...
                    'Rollback prune failed: %s', pruneErr.message);
        end
        rethrow(ME);
    end
end

function rmTempDir(d)
    if exist(d, 'dir')
        rmdir(d, 's');
    end
end
