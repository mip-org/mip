function snapshot = snapshot_loaded()
%SNAPSHOT_LOADED   Capture the current loaded-package state.
%
% Returns the loaded and directly-loaded package lists as they are now.
% Pass the snapshot to mip.ops.reload_missing after an operation that
% unloads packages (update, @version replacement) to reload whatever the
% operation left unloaded, preserving the direct-vs-transitive distinction.

    snapshot = struct();
    snapshot.loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
    snapshot.directlyLoaded = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
end
