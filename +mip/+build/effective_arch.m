function arch = effective_arch(fqn)
%EFFECTIVE_ARCH   Effective architecture of an installed package.
%
% Usage:
%   arch = mip.build.effective_arch(fqn)
%
% Returns the *effective* architecture recorded in the package's mip.json:
% the concrete arch a matching build was compiled for (macos_arm64,
% linux_x86_64, windows_x86_64, ...), or 'any' for the pure-MATLAB fallback
% build, which ships no compiled MEX.
%
% This is distinct from mip.build.arch(), the *current* architecture of the
% machine MATLAB is running on. The current arch is always a concrete tag;
% the effective arch may be 'any'. For example, an `any` build produced on a
% macos_arm64 runner has current arch macos_arm64 but effective arch 'any'.
% To decide whether a package actually ships MEX, use mip.build.has_mex,
% which checks for the files themselves rather than the declared arch.
%
% fqn must be a fully-qualified name.

r = mip.parse.parse_package_arg(fqn);
if ~r.is_fqn
    error('mip:invalidFqn', ...
          'mip.build.effective_arch requires a fully qualified name; got "%s".', fqn);
end

pkgDir  = mip.paths.get_package_dir(fqn);
pkgInfo = mip.config.read_package_json(pkgDir);
if ~isfield(pkgInfo, 'architecture') || isempty(pkgInfo.architecture)
    error('mip:build:noArchitecture', ...
          'mip.json for "%s" has no architecture field.', fqn);
end
arch = pkgInfo.architecture;

end
