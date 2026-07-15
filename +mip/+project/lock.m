function lock(varargin)
%LOCK   Resolve mip.yaml and write mip.lock.
%
% Usage:
%   mip project lock             - Resolve the spec into mip.lock
%   mip project lock --upgrade   - Re-resolve to the newest permitted versions
%
% Resolves the nearest mip.yaml (the base dependency list plus every
% dependency group) against mip-org/core and the spec's channels, and
% writes the full transitive closure to mip.lock in dependency-first
% order - each entry carrying the resolved version and architecture, the
% exact .mhl URL and its SHA-256 (as published by the channel index),
% commit/source hashes for traceability, a direct flag for the packages
% named in the spec, and the groups that require it. "mip project sync"
% reinstalls from the lock with no network resolution.
%
% Locking installs nothing. Without --upgrade, versions recorded in an
% existing mip.lock are kept when the channel still publishes them; spec
% @version pins always win. Creating mip.lock is what opts the directory
% into the declarative (uv) mode; commit it alongside mip.yaml.

    [opts, args] = mip.parse.flags(varargin, ...
        struct('upgrade', false, 'directory', ''));
    if ~isempty(args)
        error('mip:project:tooManyArgs', ...
              '"mip project lock" takes no package arguments; edit mip.yaml or use "mip project add".');
    end

    proj = mip.project.locate(opts.directory);
    mip.project.lock_project(proj, opts.upgrade);

end
