function add(varargin)
%ADD   Add one or more dependencies to the project environment.
%
% Usage:
%   mip env add <package> [<package> ...]
%   mip env add --channel <owner>/<channel> <package>
%   mip env add --directory <dir> <package>
%   mip env add <package> --no-sync
%
% Options:
%   --channel <name>   Channel the package(s) come from. When given, each
%                      package is recorded in mipenv.yaml as a fully
%                      qualified <owner>/<channel>/<name> so its origin is
%                      pinned. Without it, bare names resolve against
%                      mip-org/core plus the spec's channels.
%   --directory <dir>  Project directory (default: current).
%   --no-sync          Update mipenv.yaml and mipenv.lock but do not install.
%
% Adds the packages to mipenv.yaml, re-resolves mipenv.lock, and (unless
% --no-sync) installs the environment. Creates mipenv.yaml if absent. This
% is the analog of "uv add".

    [opts, packages] = mip.parse.flags(varargin, ...
        struct('channel', '', 'directory', '', 'no_sync', false));
    if isempty(packages)
        error('mip:env:noPackage', ...
              'At least one package name is required for "mip env add".');
    end

    projectDir = mip.env.project_dir(opts.directory);

    % Create a spec on the fly if the project has none yet.
    if ~exist(mip.env.spec_path(projectDir), 'file')
        mip.env.init('--directory', projectDir);
        fprintf('\n');
    end
    spec = mip.env.read_spec(projectDir);

    channel = opts.channel;
    if ~isempty(channel)
        channel = mip.parse.normalize_channel_spec(channel);
    end

    for i = 1:numel(packages)
        depStr = build_dep_string(packages{i}, channel);
        if any(strcmp(spec.dependencies, depStr))
            fprintf('Already a dependency: %s\n', depStr);
        else
            spec.dependencies{end+1} = depStr;
            fprintf('Added dependency: %s\n', depStr);
        end
    end

    mip.env.write_spec(projectDir, spec);

    if opts.no_sync
        mip.env.lock('--directory', projectDir);
    else
        mip.env.sync('--directory', projectDir, '--relock');
    end
end

function depStr = build_dep_string(pkgArg, channel)
% Produce the dependency string to store in mipenv.yaml. With an explicit
% channel (and a bare package name), pin it as a fully qualified name so the
% origin is unambiguous. FQN args and channel-less bare names are stored
% as-is (preserving any @version suffix).
    parsed = mip.parse.parse_package_arg(pkgArg);
    if isempty(channel) || parsed.is_fqn
        depStr = pkgArg;
        return
    end
    [owner, ch, name, version] = mip.resolve.resolve_package_name(pkgArg, channel);
    depStr = sprintf('%s/%s/%s', owner, ch, name);
    if ~isempty(version)
        depStr = sprintf('%s@%s', depStr, version);
    end
end
