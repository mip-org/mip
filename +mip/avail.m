function avail(varargin)
%AVAIL   Display a list of all available packages.
%
% Usage:
%   mip avail
%   mip avail --channel <owner>/<channel>
%   mip avail --channel <owner>             - Shorthand for --channel <owner>/<owner>
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

[opts, ~] = mip.parse.flags(varargin, struct('channel', ''));
channel = opts.channel;

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
