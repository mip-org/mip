function tf = is_own_root()
%IS_OWN_ROOT   True when the active root is the root mip actually runs from.
%
% Usage:
%   tf = mip.self.is_own_root()
%
% The self flows — self-uninstall (which tears down the entire root) and
% the self-update/self-install hot swap — must only trigger against the
% root that contains the running mip. In any other active root (an
% activated environment, or an external MIP_ROOT pointing elsewhere),
% gh/mip-org/core/mip is an ordinary, inert package: installing, updating,
% or uninstalling it there must never touch the running mip or tear down
% that root.
%
% The running mip is located via which('mip', '-all') — every mip.m
% reachable on the MATLAB path — and the active root is mip's own root
% when its gh/mip-org/core/mip package's source directory is among those
% locations. An environment's copy is never on the path (mip load mip is
% a no-op), so it never matches. Membership (rather than the single
% which('mip') winner) keeps the check correct when something shadows
% mip.m, e.g. the user's current folder. Returns false when the active
% root has no such package installed.

tf = false;

pkgDir = mip.paths.get_package_dir('gh/mip-org/core/mip');
if ~isfolder(pkgDir)
    return
end

% Resolve the package's source directory the same way load does (an
% editable install of mip points at its checkout via source_path).
try
    pkgInfo = mip.config.read_package_json(pkgDir);
    srcDir = mip.paths.get_source_dir(pkgDir, pkgInfo);
catch
    srcDir = fullfile(pkgDir, 'mip');
end

candidates = which('mip', '-all');
for i = 1:numel(candidates)
    if paths_equal(fileparts(candidates{i}), srcDir)
        tf = true;
        return
    end
end

end

function tf = paths_equal(a, b)
    a = strip_trailing_sep(a);
    b = strip_trailing_sep(b);
    if ispc
        tf = strcmpi(a, b);
    else
        tf = strcmp(a, b);
    end
end

function p = strip_trailing_sep(p)
    while length(p) > 1 && (p(end) == '/' || p(end) == '\')
        p = p(1:end-1);
    end
end
