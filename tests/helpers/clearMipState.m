function clearMipState()
%CLEARMIPSTATE   Clear all mip-related persistent state from appdata.
%
% MIP_SELF_ROOT is the test seam for mip.self.is_active_root: tests run
% mip from a source checkout, which is not installed into any root, so a
% test that exercises the self- flows (self-uninstall, self-update, the
% install-time hot swap) sets this key to the root under test.

keys = {'MIP_LOADED_PACKAGES', 'MIP_DIRECTLY_LOADED_PACKAGES', ...
        'MIP_STICKY_PACKAGES', 'MIP_TEST_CONTEXT', ...
        'MIP_ACTIVE_ENV', 'MIP_SELF_ROOT'};
for i = 1:length(keys)
    if isappdata(0, keys{i})
        rmappdata(0, keys{i});
    end
end

end
