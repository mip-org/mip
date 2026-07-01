function reload_missing(snapshot)
%RELOAD_MISSING   Reload snapshotted packages that are no longer loaded.
%
% For each package in snapshot.loaded (from mip.ops.snapshot_loaded) that
% is not currently loaded, load it again — with --transitive when it was
% not directly loaded, so the direct-vs-transitive distinction survives an
% unload/reinstall cycle. Packages that are no longer installed are
% skipped with a warning line.

    if isempty(snapshot.loaded)
        return
    end

    for i = 1:length(snapshot.loaded)
        pkg = snapshot.loaded{i};
        if mip.state.is_loaded(pkg)
            continue
        end
        r = mip.parse.parse_package_arg(pkg);
        if ~r.is_fqn
            continue
        end
        pkgDir = mip.paths.get_package_dir(pkg);
        displayPkg = mip.parse.display_fqn(pkg);
        if ~exist(pkgDir, 'dir')
            fprintf('Warning: "%s" was loaded but is no longer installed; skipping reload.\n', displayPkg);
            continue
        end
        fprintf('Reloading "%s"...\n', displayPkg);
        if ismember(pkg, snapshot.directlyLoaded)
            mip.load(pkg);
        else
            mip.load(pkg, '--transitive');
        end
    end
end
