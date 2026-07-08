function sync(varargin)
%SYNC   Install the project environment to match mipenv.lock exactly.
%
% Usage:
%   mip env sync
%   mip env sync --directory <dir>
%   mip env sync --relock
%
% Options:
%   --directory <dir>  Project directory (default: current).
%   --relock           Re-resolve the spec and rewrite mipenv.lock before
%                      installing (equivalent to "mip env lock" then sync).
%
% Installs every package recorded in mipenv.lock into the project-local root
% (<dir>/.mip), downloading each package's exact locked .mhl and verifying
% its SHA-256. Packages already present are left untouched. This is the
% analog of "uv sync": the lock is the source of truth, so no re-resolution
% happens unless --relock is given (or no lock exists yet).
%
% If a locked package was built for a different architecture than the
% current machine, sync re-resolves that single package from its channel to
% obtain the right binary for this platform (the version pin is preserved).

    [opts, positionals] = mip.parse.flags(varargin, ...
        struct('directory', '', 'relock', false));
    if ~isempty(positionals)
        error('mip:env:unexpectedArg', ...
              'Unexpected argument: %s', positionals{1});
    end

    projectDir = mip.env.project_dir(opts.directory);
    root = mip.env.env_root(projectDir, true);
    guard = mip.env.with_root(root); %#ok<NASGU>

    % Ensure a lock exists (and refresh it if asked).
    if opts.relock || ~exist(mip.env.lock_path(projectDir), 'file')
        spec = mip.env.read_spec(projectDir);
        fprintf('Resolving %d dependenc(ies)...\n', numel(spec.dependencies));
        lockData = mip.env.resolve_lock(spec);
        mip.env.write_lock(projectDir, lockData);
    else
        lockData = mip.env.read_lock(projectDir);
    end

    mip.paths.purge_trash();

    currentArch = mip.build.arch();
    installed = 0;
    skipped = 0;
    for i = 1:numel(lockData.packages)
        entry = lockData.packages{i};
        fqn = entry.fqn;
        display = mip.parse.display_fqn(fqn);
        pkgDir = mip.paths.get_package_dir(fqn);

        if exist(pkgDir, 'dir')
            fprintf('  = %s %s (already installed)\n', display, entry.version);
            skipped = skipped + 1;
        elseif needs_rearch(entry, currentArch)
            % Locked binary is for another platform; re-resolve this exact
            % version from its channel to get the current-arch build.
            fprintf('  ~ %s %s (locked for %s; fetching %s build)\n', ...
                    display, entry.version, entry.architecture, currentArch);
            spec_arg = sprintf('%s/%s/%s@%s', entry.owner, entry.channel, ...
                               entry.name, entry.version);
            mip.install('--channel', [entry.owner '/' entry.channel], spec_arg);
            installed = installed + 1;
        else
            fprintf('  + %s %s\n', display, entry.version);
            install_from_lock(entry, pkgDir);
            installed = installed + 1;
        end

        % Record spec-level (direct) packages as directly installed so the
        % project's prune logic keeps them and their deps.
        if isfield(entry, 'direct') && entry.direct
            mip.state.add_directly_installed(fqn);
        end
    end

    fprintf('\nEnvironment synced: %d installed, %d already present.\n', ...
            installed, skipped);
    fprintf('Root: %s\n', root);
    fprintf('Load into a MATLAB session with: mip env activate --directory %s\n', ...
            projectDir);
end

function tf = needs_rearch(entry, currentArch)
% True if the locked variant's architecture is platform-specific and does
% not match the current machine. "any" builds run everywhere.
    a = '';
    if isfield(entry, 'architecture')
        a = entry.architecture;
    end
    tf = ~isempty(a) && ~strcmp(a, 'any') && ~strcmp(a, currentArch);
end

function install_from_lock(entry, pkgDir)
% Download the exact locked .mhl (verifying its SHA-256) and install it into
% pkgDir. Mirrors the installer's download/extract/move, driven by the lock.
    if isempty(entry.mhl_url)
        error('mip:env:noMhlUrl', ...
              'Lock entry for "%s" has no mhl_url; run "mip env lock" again.', ...
              mip.parse.display_fqn(entry.fqn));
    end
    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rm_dir(tempDir));

    expectedSha = '';
    if isfield(entry, 'mhl_sha256')
        expectedSha = entry.mhl_sha256;
    end

    mhlPath = mip.channel.download_mhl(entry.mhl_url, tempDir, expectedSha);
    stagingDir = fullfile(tempDir, 'staging');
    mip.channel.extract_mhl(mhlPath, stagingDir);

    parentDir = fileparts(pkgDir);
    if ~exist(parentDir, 'dir')
        mkdir(parentDir);
    end
    movefile(stagingDir, pkgDir);
end

function rm_dir(d)
    if exist(d, 'dir')
        rmdir(d, 's');
    end
end
