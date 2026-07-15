function hex = spec_hash(projectDir)
%SPEC_HASH   SHA-256 of a project's mip.yaml, for lock staleness checks.
%
% Usage:
%   hex = mip.project.spec_hash(projectDir)
%
% mip.lock records the hash of the mip.yaml it was resolved from;
% "the spec is newer than the lock" is a content-hash mismatch, not an
% mtime comparison (which fresh clones would defeat).
%
% Returns '' when the hash cannot be computed (no JVM, unreadable file);
% callers treat an empty hash on either side as "cannot tell" rather
% than as drift.

hex = mip.channel.sha256(fullfile(projectDir, 'mip.yaml'));

end
