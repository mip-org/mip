function reset()
%RESET   Reset mip to a clean state.
%
% Usage:
%   mip reset
%
% Unloads all packages (including sticky ones, excluding mip itself) and
% removes all MIP key-value stores from persistent storage.

% Unload all packages (force mode: includes sticky packages)
mip.unload('--all', '--force');

% Remove all MIP key-value stores
keys = {'MIP_LOADED_PACKAGES', 'MIP_DIRECTLY_LOADED_PACKAGES', 'MIP_STICKY_PACKAGES'};
for i = 1:length(keys)
    if isappdata(0, keys{i})
        rmappdata(0, keys{i});
    end
end

fprintf('mip has been reset\n');

end
