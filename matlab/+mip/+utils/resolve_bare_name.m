function fqn = resolve_bare_name(packageName)
%RESOLVE_BARE_NAME   Resolve a bare package name to its fully qualified name.
%
% Searches installed packages for a bare name match. Resolution priority:
%   1. mip-org/core (the default channel)
%   2. First alphabetically by org/channel
%
% Args:
%   packageName - Bare package name (e.g. 'chebfun')
%
% Returns:
%   fqn - Fully qualified name, or empty string if not found

fqn = '';

packagesDir = mip.utils.get_packages_dir();
if ~exist(packagesDir, 'dir')
    return
end

% Collect all matches: scan org/channel/packageName directories
matches = {};

orgDirs = dir(packagesDir);
for i = 1:length(orgDirs)
    if ~orgDirs(i).isdir || startsWith(orgDirs(i).name, '.')
        continue
    end
    org = orgDirs(i).name;
    orgPath = fullfile(packagesDir, org);

    chanDirs = dir(orgPath);
    for j = 1:length(chanDirs)
        if ~chanDirs(j).isdir || startsWith(chanDirs(j).name, '.')
            continue
        end
        ch = chanDirs(j).name;
        pkgDir = fullfile(orgPath, ch, packageName);
        if exist(pkgDir, 'dir')
            matches{end+1} = mip.utils.make_fqn(org, ch, packageName); %#ok<AGROW>
        end
    end
end

if isempty(matches)
    return
end

% Priority: local/editable first (editable installs take precedence)
for i = 1:length(matches)
    if startsWith(matches{i}, 'local/editable/')
        fqn = matches{i};
        return
    end
end

% Then mip-org/core
for i = 1:length(matches)
    if startsWith(matches{i}, 'mip-org/core/')
        fqn = matches{i};
        return
    end
end

% Otherwise, first alphabetically
matches = sort(matches);
fqn = matches{1};

end
