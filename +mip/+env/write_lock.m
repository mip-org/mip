function write_lock(projectDir, lockData)
%WRITE_LOCK   Serialize resolved lock data to mipenv.lock (JSON).
%
% Args:
%   projectDir - Project directory (from mip.env.project_dir).
%   lockData   - Struct from mip.env.resolve_lock.
%
% The file is JSON so it round-trips through MATLAB's native jsonencode /
% jsondecode with no third-party YAML/TOML dependency. It is generated, not
% hand-edited; regenerate it with "mip env lock".

lockFile = mip.env.lock_path(projectDir);

% jsonencode emits a cell array of structs as a JSON array of objects, which
% is what we want for .packages. Pretty-print for human-readable diffs.
json = jsonencode(lockData, 'PrettyPrint', true);

fid = fopen(lockFile, 'w');
if fid == -1
    error('mip:env:lockWriteFailed', 'Could not open %s for writing.', lockFile);
end
cleaner = onCleanup(@() fclose(fid));
fwrite(fid, json, 'char');

end
