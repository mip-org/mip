function srcDir = createTestSourcePackage(baseDir, pkgName, varargin)
%CREATETESTSOURCEPACKAGE   Create a source package directory with mip.yaml.
%
% Creates a directory with mip.yaml and a simple MATLAB function,
% suitable for testing mip.utils.install_local.
%
% Args:
%   baseDir - Parent directory to create the package in
%   pkgName - Package name
%
% Optional name-value pairs:
%   'version'      - Version string (default: '1.0.0')
%   'dependencies' - Cell array of dependency names (default: {})
%
% Returns:
%   srcDir - The created source directory path

p = inputParser;
addParameter(p, 'version', '1.0.0', @ischar);
addParameter(p, 'dependencies', {}, @iscell);
parse(p, varargin{:});

srcDir = fullfile(baseDir, pkgName);
mkdir(srcDir);

% Create mip.yaml
fid = fopen(fullfile(srcDir, 'mip.yaml'), 'w');
fprintf(fid, 'name: %s\n', pkgName);
fprintf(fid, 'version: "%s"\n', p.Results.version);
fprintf(fid, 'description: "Test source package %s"\n', pkgName);
fprintf(fid, 'license: MIT\n');
fprintf(fid, 'dependencies: [');
deps = p.Results.dependencies;
if ~isempty(deps)
    fprintf(fid, '%s', strjoin(deps, ', '));
end
fprintf(fid, ']\n');
fprintf(fid, '\n');
fprintf(fid, 'addpaths:\n');
fprintf(fid, '  - path: "."\n');
fprintf(fid, '\n');
fprintf(fid, 'builds:\n');
fprintf(fid, '  - architectures: [any]\n');
fclose(fid);

% Create a simple MATLAB function
fid = fopen(fullfile(srcDir, [pkgName '.m']), 'w');
fprintf(fid, 'function result = %s()\n', pkgName);
fprintf(fid, '    result = ''hello from %s'';\n', pkgName);
fprintf(fid, 'end\n');
fclose(fid);

end
