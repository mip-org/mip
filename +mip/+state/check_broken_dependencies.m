function check_broken_dependencies(mode)
%CHECK_BROKEN_DEPENDENCIES   Warn about packages with missing dependencies.
%
% Args:
%   mode - 'installed' to check installed packages for uninstalled deps,
%          'loaded' to check loaded packages for unloaded deps.

if strcmp(mode, 'installed')
    packages = mip.state.list_installed_packages();
    missingVerb = 'not installed';
    contextNoun = 'installed';
else
    packages = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    missingVerb = 'no longer loaded';
    contextNoun = 'loaded';
end

if isempty(packages)
    return
end

brokenDeps = {};
for i = 1:length(packages)
    pkg = packages{i};
    r = mip.parse.parse_package_arg(pkg);
    if ~r.is_fqn
        continue
    end

    packageDir = mip.paths.get_package_dir(pkg);
    mipJsonPath = fullfile(packageDir, 'mip.json');

    if ~exist(mipJsonPath, 'file')
        continue
    end

    try
        pkgInfo = mip.config.read_package_json(packageDir);

        if isempty(pkgInfo.dependencies)
            continue
        end

        depNames = pkgInfo.dependencies;
        for j = 1:length(depNames)
            dep = depNames{j};
            if strcmp(mode, 'installed')
                depMissing = isDependencyUninstalled(dep, pkg);
            else
                depMissing = isDependencyUnloaded(dep, pkg);
            end
            if depMissing
                brokenDeps{end+1} = sprintf('Package "%s" depends on "%s" which is %s', pkg, dep, missingVerb); %#ok<AGROW>
            end
        end
    catch
        % Silently ignore parse errors
    end
end

if ~isempty(brokenDeps)
    warning('mip:brokenDependencies', ...
            'Warning: Some %s packages have missing dependencies:\n  %s', ...
            contextNoun, strjoin(brokenDeps, '\n  '));
end

end

function tf = isDependencyUninstalled(dep, parentFqn)
    tf = ~isempty(mip.dependency.find_missing({dep}, parentFqn));
end

function tf = isDependencyUnloaded(dep, parentFqn)
    depFqn = mip.resolve.resolve_dependency(dep, parentFqn);
    tf = ~mip.state.is_loaded(depFqn);
end
