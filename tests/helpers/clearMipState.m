function clearMipState()
%CLEARMIPSTATE   Clear all mip-related persistent state from appdata.

keys = {'MIP_LOADED_PACKAGES', 'MIP_DIRECTLY_LOADED_PACKAGES', 'MIP_STICKY_PACKAGES'};
for i = 1:length(keys)
    if isappdata(0, keys{i})
        rmappdata(0, keys{i});
    end
end

end
