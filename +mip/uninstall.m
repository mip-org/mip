function uninstall(varargin)
%UNINSTALL   Uninstall one or more mip packages.
%
% Usage:
%   mip uninstall <package>
%   mip uninstall <owner>/<channel>/<package>
%   mip uninstall <package1> <package2> ...
%
% Accepts both bare package names and fully qualified names.
% This function uninstalls packages and then prunes any packages that
% are no longer needed (packages that were installed as dependencies
% but are not dependencies of any directly installed package).
%
% "mip uninstall mip" is the full teardown of mip and its root. It is
% allowed only from a plain session on the main root: not while an
% environment is active (deactivate first), not while another mip is
% loaded (unload it first), and never for a standalone mip (the root is
% never deleted in standalone mode).

    if nargin < 1
        error('mip:uninstall:noPackage', ...
              'At least one package name is required for uninstall command.');
    end

    % Show the target when an environment is active (session state has no
    % shell prompt to reflect it).
    mip.env.print_banner();

    % Opportunistically reclaim package dirs that an earlier removal could
    % only move aside (a binary was still loaded in that session).
    mip.paths.purge_trash();

    packageArgs = varargin;

    % Resolve all package arguments to FQNs. Arguments that name the self
    % identity but resolve to nothing installed are tracked separately:
    % the self-operation guards below decide how to report them (a plain
    % "not installed" would be wrong for e.g. a standalone mip).
    notInstalled = {};
    resolvedPackages = {};
    unresolvedSelf = false;

    for i = 1:length(packageArgs)
        arg = packageArgs{i};
        result = mip.parse.parse_package_arg(arg);

        if result.is_fqn
            % Canonicalize to the on-disk name so the stored FQN we
            % remove from directly_installed.txt matches what was added
            % during install.
            fqn = mip.resolve.installed_fqn(result.fqn);
            if isempty(fqn)
                fqn = result.fqn;
            end
            pkgDir = mip.paths.get_package_dir(fqn);
        else
            allMatches = mip.resolve.find_all_installed_by_name(result.name);
            if isempty(allMatches)
                if mip.name.match(result.name, 'mip')
                    unresolvedSelf = true;
                else
                    notInstalled = [notInstalled, {arg}]; %#ok<*AGROW>
                end
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
            if mip.self.is_identity(mip.parse.parse_package_arg(fqn))
                unresolvedSelf = true;
            else
                notInstalled = [notInstalled, {arg}];
            end
        else
            resolvedPackages = [resolvedPackages, {fqn}];
        end
    end

    % Self-operation guards: gh/mip-org/core/mip names the main mip. Its
    % uninstall — the full root teardown — is allowed only from a plain
    % session on the main root with no other mip loaded (specification
    % §1.7.1). In a standalone session the identity is at most an inert
    % copy: uninstalling an installed copy proceeds as an ordinary
    % package, and with none installed there is no teardown to run.
    resolvedSelf = ismember('gh/mip-org/core/mip', resolvedPackages);
    if resolvedSelf || unresolvedSelf
        s = mip.self.op_state();
        switch s.state
            case 'ok'
                if uninstallSelf()
                    return
                end
                resolvedPackages = resolvedPackages(~strcmp(resolvedPackages, 'gh/mip-org/core/mip'));
            case 'standalone'
                if unresolvedSelf
                    fprintf(['The running mip is standalone — not installed in the main ' ...
                             'root — so there is no teardown to run; the root is never ' ...
                             'deleted in standalone mode.\n' ...
                             'To remove a standalone mip, delete its folder and remove ' ...
                             'it from the MATLAB path.\n']);
                end
                % A resolved inert copy stays in the list and is
                % uninstalled as an ordinary package below.
            case 'env'
                error('mip:self:envActive', ...
                      ['Cannot uninstall the main mip while an environment is ' ...
                       'active. Run "mip deactivate" first.']);
            case 'mip-loaded'
                blockers = cellfun(@mip.parse.display_fqn, s.blockers, 'UniformOutput', false);
                error('mip:self:otherMipLoaded', ...
                      ['Cannot uninstall the main mip while another mip is ' ...
                       'loaded (%s). Run "mip unload %s" first.'], ...
                      strjoin(blockers, ', '), blockers{end});
        end
    end

    % A package whose code is currently running cannot be uninstalled
    % while loaded (Scenario 13): removing it would pull the running
    % mip's files out from under the session.
    runningMip = mip.self.running_mip_fqn();
    if ~isempty(runningMip) && ismember(runningMip, resolvedPackages) && ...
            mip.state.is_loaded(runningMip)
        error('mip:uninstall:runningMip', ...
              ['Package "%s" provides the running mip and cannot be uninstalled ' ...
               'while it is loaded. Run "mip unload %s" first.'], ...
              mip.parse.display_fqn(runningMip), mip.parse.display_fqn(runningMip));
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

        % The self identity reaches this loop only when the active root is
        % not the one mip runs from; its copy there is inert (never on the
        % path), so there is nothing to unload — and mip.unload would
        % refuse the identity anyway.
        if mip.state.is_loaded(fqn) && ~strcmp(fqn, 'gh/mip-org/core/mip')
            mip.unload(fqn);
        end

        fprintf('Uninstalling "%s"...\n', displayFqn);
        removePackageDir(pkgDir, displayFqn);
        fprintf('Uninstalled package "%s"\n', displayFqn);

        % Remove from directly installed and pinned packages
        mip.state.remove_directly_installed(fqn);
        mip.state.remove_pinned(fqn);

        % Clean up empty parent directories (derived from the FQN layout)
        mip.paths.cleanup_package_parents(fqn);
    end

    % Prune packages that are no longer needed
    mip.state.prune_unused_packages();

    % After pruning, check for broken dependencies
    mip.state.check_broken_dependencies('installed');
end

function removePackageDir(pkgDir, displayFqn)
% Remove an installed package directory robustly (see mip.paths.remove_dir).
% A loaded native binary on Windows can keep the directory from being
% deleted in-session; remove_dir moves it into the mip trash so the
% uninstall completes immediately and the leftover is purged on a later run.
    try
        mip.paths.remove_dir(pkgDir);
    catch rmErr
        error('mip:uninstallFailed', ...
              'Failed to uninstall package "%s": %s', displayFqn, rmErr.message);
    end
end

function didUninstall = uninstallSelf()
% Completely uninstall mip: reset state, remove from path, delete root dir.

    mipRoot        = mip.paths.root();
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

    % Unload every compiled MEX across all installed packages so the whole
    % mip root can be deleted below -- a loaded DLL/MEX cannot be removed on
    % Windows. Done now, while mip is still on the MATLAB path (the helpers
    % become unreachable once mip is rmpath'd further down). Scans the entire
    % root so MEX under any previously-trashed dirs are released too.
    mip.build.clear_mex(mipRoot);

    fprintf('Removing mip from saved MATLAB path...\n');

    % Cache the user's current path
    current_path = path;

    savedOK = false;
    try
        % Change the path to match what it would be if MATLAB had just started up
        path(pathdef);

        % Remove <MIP_ROOT>/packages/gh/mip-org/core/mip/mip from the path and save it
        % for future MATLAB sessions. savepath() returns a nonzero status (rather
        % than erroring) when it cannot write pathdef.m -- common on managed or
        % shared installs where it is read-only.
        rmpath_safe(mipSourceDir);
        savedOK = savepath() == 0;
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
    if ~savedOK
        warning('mip:uninstall:savePathFailed', ...
                ['Your saved MATLAB path could not be updated. ' ...
                 'If you added an "addpath" for mip to your startup.m file, ' ...
                 'please remove it.']);
    end
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
