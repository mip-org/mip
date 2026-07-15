function write_lock(lockPath, lock)
%WRITE_LOCK   Write a project lock struct to mip.lock (JSON).
%
% Usage:
%   mip.project.write_lock(lockPath, lock)
%
% The lock is JSON despite its .lock extension (following uv.lock), so it
% round-trips through MATLAB's native jsonencode/jsondecode with no extra
% dependency. It is pretty-printed for stable, reviewable git diffs and
% contains no timestamps, so re-locking an unchanged spec produces an
% identical file.
%
% lock is a struct with fields:
%   lock_version - Lock format version (1)
%   mip_version  - Version of the mip that wrote the lock
%   spec_sha256  - SHA-256 of the mip.yaml the lock was resolved from
%                  ('' when it could not be computed)
%   packages     - Row cell array of entry structs, dependency-first
%                  order, each with fields: fqn, name, version,
%                  architecture, mhl_url, mhl_sha256, commit_hash,
%                  source_hash, dependencies (cellstr), direct (logical),
%                  base (logical), groups (cellstr)

out = struct();
out.lock_version = lock.lock_version;
out.mip_version = lock.mip_version;
out.spec_sha256 = lock.spec_sha256;

entries = cell(1, numel(lock.packages));
for i = 1:numel(lock.packages)
    p = lock.packages{i};
    e = struct();
    e.fqn = p.fqn;
    e.name = p.name;
    e.version = p.version;
    e.architecture = p.architecture;
    e.mhl_url = p.mhl_url;
    e.mhl_sha256 = p.mhl_sha256;
    e.commit_hash = p.commit_hash;
    e.source_hash = p.source_hash;
    e.dependencies = as_json_list(p.dependencies);
    e.direct = logical(p.direct);
    e.base = logical(p.base);
    e.groups = as_json_list(p.groups);
    entries{i} = e;
end
if isempty(entries)
    out.packages = reshape({}, 0, 1);
else
    out.packages = entries;
end

jsonText = jsonencode(out, 'PrettyPrint', true);

fid = fopen(lockPath, 'w');
if fid == -1
    error('mip:fileError', 'Could not write to %s', lockPath);
end
fwrite(fid, [jsonText newline]);
fclose(fid);

end

function v = as_json_list(v)
% Normalize a cellstr so jsonencode always produces a JSON array (never
% a scalar string, even for one entry).
    if isempty(v)
        v = reshape({}, 0, 1);
    else
        v = reshape(v, [], 1);
    end
end
