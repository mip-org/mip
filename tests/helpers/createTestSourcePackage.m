function srcDir = createTestSourcePackage(baseDir, pkgName, varargin)
%CREATETESTSOURCEPACKAGE   Create a source package directory with mip.yaml.
%
% Creates a directory with mip.yaml and a simple MATLAB function,
% suitable for testing mip.build.install_local.
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
addParameter(p, 'compile_script', '', @ischar);
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
compileScript = p.Results.compile_script;
if ~isempty(compileScript)
    fprintf(fid, 'compile_script: "%s"\n', compileScript);
    fprintf(fid, '\n');
end
fprintf(fid, 'addpaths:\n');
fprintf(fid, '  - path: "."\n');
fprintf(fid, '\n');
fprintf(fid, 'builds:\n');
fprintf(fid, '  - architectures: [any]\n');
fclose(fid);

% Create compile script if specified
if ~isempty(compileScript)
    compilePath = fullfile(srcDir, compileScript);
    compileParent = fileparts(compilePath);
    if ~exist(compileParent, 'dir') && ~isempty(compileParent)
        mkdir(compileParent);
    end
    fid2 = fopen(compilePath, 'w');
    fprintf(fid2, '%% Test compile script for %s\n', pkgName);
    fprintf(fid2, 'fid = fopen(fullfile(fileparts(mfilename(''fullpath'')), ''.compiled''), ''w'');\n');
    fprintf(fid2, 'fwrite(fid, ''compiled'');\n');
    fprintf(fid2, 'fclose(fid);\n');
    fclose(fid2);
end

% Create a simple MATLAB function
fid = fopen(fullfile(srcDir, [pkgName '.m']), 'w');
fprintf(fid, 'function result = %s()\n', pkgName);
fprintf(fid, '    result = ''hello from %s'';\n', pkgName);
fprintf(fid, 'end\n');
fclose(fid);

end
