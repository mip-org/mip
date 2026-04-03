function pkgDir = createTestPackage(rootDir, org, channel, pkgName, varargin)
%CREATETESTPACKAGE   Create a fake installed mip package for testing.
%
% Args:
%   rootDir  - The MIP_ROOT directory (e.g. tempdir)
%   org      - Organization name (e.g. 'mip-org')
%   channel  - Channel name (e.g. 'core')
%   pkgName  - Package name (e.g. 'testpkg')
%
% Optional name-value pairs:
%   'version'      - Version string (default: '1.0.0')
%   'dependencies' - Cell array of dependency names (default: {})
%
% Returns:
%   pkgDir - The created package directory path

p = inputParser;
addParameter(p, 'version', '1.0.0', @ischar);
addParameter(p, 'dependencies', {}, @iscell);
parse(p, varargin{:});

pkgDir = fullfile(rootDir, 'packages', org, channel, pkgName);

% Create directory tree
if ~exist(pkgDir, 'dir')
    mkdir(pkgDir);
end

% Create mip.json
mipData = struct();
mipData.name = pkgName;
mipData.version = p.Results.version;
mipData.description = ['Test package ' pkgName];
mipData.architecture = 'any';
mipData.install_type = 'test';

deps = p.Results.dependencies;
if isempty(deps)
    mipData.dependencies = reshape({}, 0, 1);
else
    mipData.dependencies = deps;
end

fid = fopen(fullfile(pkgDir, 'mip.json'), 'w');
fwrite(fid, jsonencode(mipData));
fclose(fid);

% Create load_package.m
fid = fopen(fullfile(pkgDir, 'load_package.m'), 'w');
fprintf(fid, 'function load_package()\n');
fprintf(fid, '    pkg_dir = fileparts(mfilename(''fullpath''));\n');
fprintf(fid, '    addpath(pkg_dir);\n');
fprintf(fid, 'end\n');
fclose(fid);

% Create unload_package.m
fid = fopen(fullfile(pkgDir, 'unload_package.m'), 'w');
fprintf(fid, 'function unload_package()\n');
fprintf(fid, '    pkg_dir = fileparts(mfilename(''fullpath''));\n');
fprintf(fid, '    if ismember(pkg_dir, strsplit(path, pathsep))\n');
fprintf(fid, '        rmpath(pkg_dir);\n');
fprintf(fid, '    end\n');
fprintf(fid, 'end\n');
fclose(fid);

end
