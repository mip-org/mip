function check_broken_dependencies(mode)
%CHECK_BROKEN_DEPENDENCIES   Warn about packages with missing dependencies.
%
% Args:
%   mode - 'installed' to check installed packages for uninstalled deps,
%          'loaded' to check loaded packages for unloaded deps.

if strcmp(mode, 'installed')
    packages = mip.utils.list_installed_packages();
    missingVerb = 'not installed';
    contextNoun = 'installed';
else
    packages = mip.utils.key_value_get('MIP_LOADED_PACKAGES');
    missingVerb = 'no longer loaded';
    contextNoun = 'loaded';
end

if isempty(packages)
    return
end

brokenDeps = {};
for i = 1:length(packages)
    pkg = packages{i};
    r = mip.utils.parse_package_arg(pkg);
    if ~r.is_fqn
        continue
    end

    packageDir = mip.utils.get_package_dir(r.org, r.channel, r.name);
    mipJsonPath = fullfile(packageDir, 'mip.json');

    if ~exist(mipJsonPath, 'file')
        continue
    end

    try
        pkgInfo = mip.utils.read_package_json(packageDir);

        if isempty(pkgInfo.dependencies)
            continue
        end

        depNames = pkgInfo.dependencies;
        if ~iscell(depNames)
            depNames = {depNames};
        end
        for j = 1:length(depNames)
            dep = depNames{j};
            if strcmp(mode, 'installed')
                depMissing = isDependencyUninstalled(dep);
            else
                depMissing = isDependencyUnloaded(dep);
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

function tf = isDependencyUninstalled(dep)
    depResult = mip.utils.parse_package_arg(dep);
    if depResult.is_fqn
        depDir = mip.utils.get_package_dir(depResult.org, depResult.channel, depResult.name);
        tf = ~exist(depDir, 'dir');
    else
        resolved = mip.utils.resolve_bare_name(dep);
        tf = isempty(resolved);
    end
end

function tf = isDependencyUnloaded(dep)
    depResult = mip.utils.parse_package_arg(dep);
    if depResult.is_fqn
        depFqn = dep;
    else
        depFqn = mip.utils.resolve_bare_name(dep);
    end
    tf = isempty(depFqn) || ~mip.utils.is_loaded(depFqn);
end
