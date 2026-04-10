function avail(varargin)
%AVAIL   Display a list of all available packages.
%
% Usage:
%   mip.avail()
%   mip.avail('--channel', 'dev')
%   mip.avail('--channel', 'owner/channel')
%
% Options:
%   --channel <name>  List packages from a specific channel (default: mip-org/core)
%                     Format: 'org/channel' (e.g. 'mip-org/core')
%
% Displays an alphabetical list of all available packages in the online
% repository for the current architecture, shown with fully qualified names.

[channel, ~] = mip.parse.parse_channel_flag(varargin);

if isempty(channel)
    channel = 'mip-org/core';
end

[org, channelName] = mip.parse.parse_channel_spec(channel);

try
    indexUrl = mip.index(channel);
    fprintf('Using channel: %s/%s\n', org, channelName);
    tempFile = [tempname, '.json'];
    websave(tempFile, indexUrl, weboptions('Timeout', 60));
    indexJson = fileread(tempFile);
    delete(tempFile);

    index = jsondecode(indexJson);

    % Get current architecture
    currentArch = mip.arch();

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
                fqn = mip.parse.make_fqn(org, channelName, pkg.name);
                if ~ismember(fqn, availablePackages)
                    availablePackages = [availablePackages, {fqn}]; %#ok<AGROW>
                end
            end
        end
    end

    % Sort alphabetically
    availablePackages = sort(availablePackages);

    % Display the list
    fprintf('\nAvailable packages for %s:\n\n', currentArch);
    for i = 1:length(availablePackages)
        fprintf('  %s\n', availablePackages{i});
    end
    fprintf('\n');

catch ME
    error('mip:availFailed', ...
          'Failed to retrieve available packages: %s', ME.message);
end

end
