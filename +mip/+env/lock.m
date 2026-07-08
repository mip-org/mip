function lock(varargin)
%LOCK   Resolve the spec's dependencies and write mipenv.lock.
%
% Usage:
%   mip env lock
%   mip env lock --directory <dir>
%
% Options:
%   --directory <dir>  Project directory (default: current).
%
% Reads mipenv.yaml, resolves every dependency (and its transitive
% dependencies) against the channel indexes to concrete versions and
% download URLs, and writes the result to mipenv.lock. Does not install
% anything -- run "mip env sync" for that. This is the analog of "uv lock".

    [opts, positionals] = mip.parse.flags(varargin, struct('directory', ''));
    if ~isempty(positionals)
        error('mip:env:unexpectedArg', ...
              'Unexpected argument: %s', positionals{1});
    end

    projectDir = mip.env.project_dir(opts.directory);
    spec = mip.env.read_spec(projectDir);

    root = mip.env.env_root(projectDir, true);
    guard = mip.env.with_root(root); %#ok<NASGU>

    fprintf('Resolving %d dependenc(ies) for environment...\n', ...
            numel(spec.dependencies));
    lockData = mip.env.resolve_lock(spec);
    mip.env.write_lock(projectDir, lockData);

    fprintf('\nLocked %d package(s) to %s:\n', ...
            numel(lockData.packages), mip.env.lock_path(projectDir));
    for i = 1:numel(lockData.packages)
        p = lockData.packages{i};
        marker = ' ';
        if isfield(p, 'direct') && p.direct
            marker = '*';
        end
        fprintf('  %s %s %s [%s]\n', marker, ...
                mip.parse.display_fqn(p.fqn), p.version, p.architecture);
    end
    fprintf('  (* = requested directly)\n');
end
