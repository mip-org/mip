function avail(varargin)
%AVAIL   Display a list of all available packages.
%
% Usage:
%   mip avail
%   mip avail --channel <owner>/<channel>
%   mip avail --channel <owner>             - Shorthand for --channel <owner>/<owner>
%   mip avail <owner>/<repo>                - Versions published by github.com/<owner>/<repo>
%
% Options:
%   --channel <name>  List packages from a specific channel (default: mip-org/core)
%                     Format: '<owner>/<channel>' (e.g. 'mip-org/core'). A bare
%                     single name '<owner>' is shorthand for '<owner>/<owner>' —
%                     the user's personal channel repo at
%                     github.com/<owner>/mip-<owner>.
%
% Displays an alphabetical list of all available packages in the online
% repository for the current architecture. Packages in the default
% mip-org/core channel are shown as bare names (bare names resolve to
% mip-org/core first, so they can be passed to "mip install" as-is);
% packages in any other channel are shown with qualified names.
%
% With a package repository argument ('<owner>/<repo>', 'gh/<owner>/<repo>',
% or 'https://github.com/<owner>/<repo>'), lists the versions and
% architectures in that repository's index instead.

[opts, args] = mip.parse.flags(varargin, struct('channel', ''));
channel = opts.channel;

if ~isempty(args)
    if length(args) > 1 || ~isempty(channel)
        error('mip:avail:invalidArgs', ...
              'Usage: mip avail [--channel <owner>/<channel>] or mip avail <owner>/<repo>.');
    end
    availRepo(char(args{1}));
    return
end

if isempty(channel)
    channel = 'mip-org/core';
else
    channel = mip.parse.normalize_channel_spec(channel);
end

[channelOwner, channelName] = mip.parse.parse_channel_spec(channel);

try
    fprintf('Using channel: %s/%s\n', channelOwner, channelName);
    index = mip.channel.fetch_index(channel, true);

    % Get current architecture
    currentArch = mip.build.arch();

    % Find all packages compatible with current architecture
    packages = index.packages;
    availablePackages = {};

    for i = 1:length(packages)
        if iscell(packages)
            pkg = packages{i};
        else
            pkg = packages(i);
        end

        if isstruct(pkg)
            if isfield(pkg, 'architecture')
                arch = pkg.architecture;
            else
                continue
            end

            canFallbackToWasm = startsWith(currentArch, 'numbl_') && ~strcmp(currentArch, 'numbl_wasm');
            if strcmp(arch, currentArch) || strcmp(arch, 'any') || (canFallbackToWasm && strcmp(arch, 'numbl_wasm'))
                if ~ismember(pkg.name, availablePackages)
                    availablePackages = [availablePackages, {pkg.name}]; %#ok<AGROW>
                end
            end
        end
    end

    % Sort alphabetically
    availablePackages = sort(availablePackages);

    % Display the list. The default mip-org/core channel is listed with
    % bare names — bare names resolve to mip-org/core first, so they can
    % be passed to "mip install" as-is. Other channels need the qualified
    % name for the install to target them.
    isCoreChannel = strcmp(channelOwner, 'mip-org') && strcmp(channelName, 'core');
    fprintf('\nAvailable packages for %s:\n\n', currentArch);
    for i = 1:length(availablePackages)
        if isCoreChannel
            fprintf('  %s\n', availablePackages{i});
        else
            fqn = mip.parse.make_fqn(channelOwner, channelName, availablePackages{i});
            fprintf('  %s\n', mip.parse.display_fqn(fqn));
        end
    end
    fprintf('\n');

catch ME
    error('mip:availFailed', ...
          'Failed to retrieve available packages: %s', ME.message);
end

end

function availRepo(arg)
% List the versions and architectures published by a package repository.
    r = mip.parse.parse_package_arg(arg);
    if ~r.is_repo
        error('mip:avail:invalidArgs', ...
              ['"%s" is not a package repository. Use "<owner>/<repo>" or ' ...
               '"https://github.com/<owner>/<repo>"; to list a channel, use ' ...
               '"mip avail --channel <owner>/<channel>".'], arg);
    end
    source = mip.channel.index_source(r.fqn);
    fprintf('Using repository: %s\n', source);
    index = mip.channel.fetch_index(source, true);
    [owner, name] = mip.channel.repo_index_identity(index, r.owner, r.name);

    % Group architectures by version.
    versionMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    pkgs = index.packages;
    for i = 1:length(pkgs)
        if iscell(pkgs)
            pkg = pkgs{i};
        else
            pkg = pkgs(i);
        end
        if ~isstruct(pkg) || ~isfield(pkg, 'version') || ~isfield(pkg, 'architecture')
            continue
        end
        if ~versionMap.isKey(pkg.version)
            versionMap(pkg.version) = {};
        end
        versionMap(pkg.version) = [versionMap(pkg.version), {pkg.architecture}];
    end

    versions = keys(versionMap);
    % Highest version first, as compare_versions orders them.
    for i = 2:length(versions)
        key = versions{i};
        j = i - 1;
        while j >= 1 && mip.resolve.compare_versions(versions{j}, key) < 0
            versions{j+1} = versions{j};
            j = j - 1;
        end
        versions{j+1} = key;
    end

    fprintf('\nAvailable versions of %s:\n\n', ...
            mip.parse.display_fqn(mip.parse.make_fqn(owner, '', name)));
    for i = 1:length(versions)
        archs = unique(versionMap(versions{i}));
        fprintf('  %s (%s)\n', versions{i}, strjoin(archs, ', '));
    end
    fprintf('\n');
end
