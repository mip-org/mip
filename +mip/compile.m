function compile(varargin)
%COMPILE   Compile (or recompile) an installed package's MEX files.
%
% Usage:
%   mip compile <package>
%   mip compile <owner>/<channel>/<package>
%
% Runs the compile script defined in the package's mip.yaml (or stored
% in mip.json for editable installs). For editable installs, compilation
% runs in the original source directory. For non-editable local installs,
% compilation runs in the installed package directory.
%
% Accepts both bare package names and fully qualified names.

if nargin < 1
    error('mip:compile:noPackage', 'Package name is required for compile command.');
end

packageArg = varargin{1};

% Resolve to installed FQN
r = mip.resolve.resolve_to_installed(packageArg);
if isempty(r)
    error('mip:compile:notInstalled', ...
          'Package "%s" is not installed.', packageArg);
end

% Read mip.json and find compile script
pkgInfo = mip.config.read_package_json(r.pkg_dir);
compileScript = mip.config.get_build_field(pkgInfo, r.pkg_dir, 'compile_script');

if isempty(compileScript)
    error('mip:compile:noCompileScript', ...
          'Package "%s" does not have a compile script defined.', mip.parse.display_fqn(r.fqn));
end

% Determine compile directory
compileDir = mip.paths.get_source_dir(r.pkg_dir, pkgInfo);

if ~isfolder(compileDir)
    error('mip:compile:sourceMissing', ...
          'Compile directory "%s" does not exist.', compileDir);
end

fprintf('Compiling "%s"...\n', mip.parse.display_fqn(r.fqn));
mip.build.run_compile(compileDir, compileScript);

end
