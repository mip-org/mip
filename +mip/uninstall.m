function uninstall(varargin)
%UNINSTALL   Uninstall one or more mip packages.
%
% Usage:
%   mip uninstall <package>
%   mip uninstall org/channel/<package>
%   mip uninstall <package1> <package2> ...
%
% Accepts both bare package names and fully qualified names.
% This function uninstalls packages and then prunes any packages that
% are no longer needed (packages that were installed as dependencies
% but are not dependencies of any directly installed package).

    if nargin < 1
        error('mip:uninstall:noPackage', ...
              'At least one package name is required for uninstall command.');
    end

    packageArgs = varargin;

    % Resolve all package arguments to FQNs
    notInstalled = {};
    resolvedPackages = {};

    for i = 1:length(packageArgs)
        arg = packageArgs{i};
        result = mip.parse.parse_package_arg(arg);

        if result.is_fqn
            % Canonicalize to the on-disk name so the stored FQN we
            % remove from directly_installed.txt matches what was added
            % during install.
            onDisk = mip.resolve.installed_dir(result.fqn);
            if isempty(onDisk)
                fqn = result.fqn;
            elseif strcmp(result.type, 'gh')
                fqn = mip.parse.make_fqn(result.org, result.channel, onDisk);
            else
                fqn = [result.type '/' onDisk];
            end
            pkgDir = mip.paths.get_package_dir(fqn);
        else
            allMatches = mip.resolve.find_all_installed_by_name(result.name);
            if isempty(allMatches)
                notInstalled = [notInstalled, {arg}]; %#ok<*AGROW>
                continue
            elseif length(allMatches) > 1
                fprintf('Package name "%s" is ambiguous. It is installed in multiple channels:\n', result.name);
                for k = 1:length(allMatches)
                    fprintf('  %s\n', mip.parse.display_fqn(allMatches{k}));
                end
                fprintf('Please specify the fully qualified name to uninstall.\n');
                continue
            end
            fqn = allMatches{1};
            pkgDir = mip.paths.get_package_dir(fqn);
        end

        if ~exist(pkgDir, 'dir')
            notInstalled = [notInstalled, {arg}];
        else
            resolvedPackages = [resolvedPackages, {fqn}];
        end
    end

    % Self-uninstall: gh/mip-org/core/mip triggers full mip removal
    if ismember('gh/mip-org/core/mip', resolvedPackages)
        if uninstallSelf()
            return
        end
        resolvedPackages = resolvedPackages(~strcmp(resolvedPackages, 'gh/mip-org/core/mip'));
    end

    % Report packages that aren't installed
    for i = 1:length(notInstalled)
        fprintf('Package "%s" is not installed\n', notInstalled{i});
    end

    if isempty(resolvedPackages)
        return
    end

    % Run each package's full lifecycle (unload, then uninstall) in
    % argument order so the output for one package is not interleaved
    % with the next.
    for i = 1:length(resolvedPackages)
        fqn = resolvedPackages{i};
        pkgDir = mip.paths.get_package_dir(fqn);
        displayFqn = mip.parse.display_fqn(fqn);

        if mip.state.is_loaded(fqn)
            mip.unload(fqn);
        end

        try
            fprintf('Uninstalling "%s"...\n', displayFqn);
            rmdir(pkgDir, 's');
            fprintf('Uninstalled package "%s"\n', displayFqn);
        catch ME
            error('mip:uninstallFailed', ...
                  'Failed to uninstall package "%s": %s', displayFqn, ME.message);
        end

        % Remove from directly installed and pinned packages
        mip.state.remove_directly_installed(fqn);
        mip.state.remove_pinned(fqn);

        % Clean up empty parent directories (derived from the FQN layout)
        cleanupPackageParents(fqn);
    end

    % Prune packages that are no longer needed
    mip.state.prune_unused_packages();

    % After pruning, check for broken dependencies
    mip.state.check_broken_dependencies('installed');
end

function cleanupPackageParents(fqn)
% Remove empty parent directories above the uninstalled package. For a
% gh FQN this walks up through <channel>, <org>, and the 'gh' root; for
% a non-gh FQN it only needs to check the source-type directory.
    packagesDir = mip.paths.get_packages_dir();
    r = mip.parse.parse_package_arg(fqn);
    if strcmp(r.type, 'gh')
        mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh', r.org, r.channel));
        mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh', r.org));
        mip.paths.cleanup_empty_dirs(fullfile(packagesDir, 'gh'));
    else
        mip.paths.cleanup_empty_dirs(fullfile(packagesDir, r.type));
    end
end

function didUninstall = uninstallSelf()
% Completely uninstall mip: reset state, remove from path, delete root dir.

    mipRoot        = mip.root();
    mipPackagesDir = mip.paths.get_packages_dir();
    mipPackageDir  = mip.paths.get_package_dir('gh/mip-org/core/mip');
    mipSourceDir   = fullfile(mipPackageDir, 'mip');

    if ~exist(mipPackagesDir, 'dir')
        error('mip:uninstall:corrupted', ...
              'The mip root directory is corrupted. Uninstallation aborted.');
    end

    fprintf('WARNING: This will completely uninstall mip.\n\n');
    fprintf('This action will:\n');
    fprintf('- Remove mip from your saved MATLAB path.\n');
    fprintf('- Unload and delete all installed packages.\n');
    fprintf('- Delete the mip root directory:\n\n');
    fprintf('  %s\n\n', shorten_home(mipRoot));
    fprintf('This cannot be undone.\n');
    confirm = getenv('MIP_CONFIRM');
    if isempty(confirm)
        confirm = input('Are you sure? (y/n): ', 's');
    end
    if ~strcmpi(confirm, 'y') && ~strcmpi(confirm, 'yes')
        didUninstall = false;
        fprintf('Uninstallation aborted.\n');
        return
    end
    didUninstall = true;

    % Reset all loaded packages and key-value stores
    mip.reset();

    fprintf('Removing mip from saved MATLAB path...\n');

    % Cache the user's current path
    current_path = path;

    try
        % Change the path to match what it would be if MATLAB had just started up
        path(pathdef);

        % Remove <MIP_ROOT>/packages/gh/mip-org/core/mip/mip from the path and save it
        % for future MATLAB sessions
        rmpath_safe(mipSourceDir);
        savepath();
    catch ME
        % Restore the user's path if anything goes wrong
        path(current_path);
        rethrow(ME);
    end

    % Restore the path to what it was before and remove
    % <MIP_ROOT>/packages/gh/mip-org/core/mip/mip from the path for the current
    % MATLAB session
    path(current_path);
    rmpath_safe(mipSourceDir);

    % Delete the mip root directory
    fprintf('Deleting %s...\n', shorten_home(mipRoot));
    rmdir(mipRoot, 's');
    fprintf('mip has been uninstalled!\n');
    fprintf('To reinstall mip, run:\n\n');
    fprintf('   eval(webread(''https://mip.sh/install.txt''))\n\n');
end

function rmpath_safe(d)
    w = warning('off', 'MATLAB:rmpath:DirNotFound');
    rmpath(d);
    warning(w);
end

function d = shorten_home(d)
    if ~(ispc || isempty(getenv('HOME')))
        d = replace(d, getenv('HOME'), '~');
    end
end
