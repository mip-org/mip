function avail(varargin)
%AVAIL   Display a list of all available packages.
%
% Usage:
%   mip.avail()
%   mip.avail('--channel', 'dev')
%
% Options:
%   --channel <name>  List packages from a specific channel (default: core)
%
% Displays an alphabetical list of all available packages in the online
% repository for the current architecture.

[channel, ~] = mip.utils.parse_channel_flag(varargin);

try
    % Download and parse package index
    indexUrl = mip.index(channel);
    if ~isempty(channel)
        fprintf('Using channel: %s\n', channel);
    end
    tempFile = [tempname, '.json'];
    websave(tempFile, indexUrl);
    indexJson = fileread(tempFile);
    delete(tempFile);

    index = jsondecode(indexJson);

    % Get current architecture
    currentArch = mip.arch();

    % Find all packages compatible with current architecture
    packages = index.packages;
    availablePackages = {};

    for i = 1:length(packages)
        % Handle both cell arrays and struct arrays
        if iscell(packages)
            pkg = packages{i};
        else
            pkg = packages(i);
        end

        if isstruct(pkg)
            % Check if architecture field exists
            if isfield(pkg, 'architecture')
                arch = pkg.architecture;
            else
                % Skip packages without architecture field
                continue
            end

            % Include if architecture matches or is 'any'
            if strcmp(arch, currentArch) || strcmp(arch, 'any')
                packageName = pkg.name;
                % Add to list if not already present
                if ~ismember(packageName, availablePackages)
                    availablePackages = [availablePackages, {packageName}]; %#ok<AGROW>
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
