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
%   'extraPaths'   - Struct mapping group name -> cell array of entries
%                    to emit under `extra_paths:`. Each entry may be a
%                    string (renders as `- "entry"`) or a struct with
%                    fields .path (required), .recursive (optional bool),
%                    .exclude (optional cell of strings).
%   'subdirs'      - Cell array of source-relative subdirs to mkdir.
%                    Each is seeded with a stub.m so compute_addpaths
%                    sees it as runtime during a recursive walk.
%
% Returns:
%   srcDir - The created source directory path

p = inputParser;
addParameter(p, 'version', '1.0.0', @ischar);
addParameter(p, 'dependencies', {}, @iscell);
addParameter(p, 'compile_script', '', @ischar);
addParameter(p, 'extraPaths', struct(), @isstruct);
addParameter(p, 'subdirs', {}, @iscell);
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
fprintf(fid, 'paths:\n');
fprintf(fid, '  - path: "."\n');
fprintf(fid, '\n');

extraPaths = p.Results.extraPaths;
if ~isempty(fieldnames(extraPaths))
    fprintf(fid, 'extra_paths:\n');
    for g = fieldnames(extraPaths)'
        fprintf(fid, '  %s:\n', g{1});
        entries = extraPaths.(g{1});
        if ~iscell(entries), entries = {entries}; end
        for k = 1:numel(entries)
            e = entries{k};
            if ischar(e)
                fprintf(fid, '    - "%s"\n', e);
            else
                fprintf(fid, '    - path: "%s"\n', e.path);
                if isfield(e, 'recursive') && e.recursive
                    fprintf(fid, '      recursive: true\n');
                end
                if isfield(e, 'exclude') && ~isempty(e.exclude)
                    exc = e.exclude;
                    if ischar(exc), exc = {exc}; end
                    fprintf(fid, '      exclude: [%s]\n', strjoin(exc, ', '));
                end
            end
        end
    end
    fprintf(fid, '\n');
end

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

% Create requested subdirs, each seeded with a stub.m.
for k = 1:numel(p.Results.subdirs)
    sub = fullfile(srcDir, p.Results.subdirs{k});
    if ~exist(sub, 'dir')
        mkdir(sub);
    end
    stubFile = fullfile(sub, 'stub.m');
    if ~exist(stubFile, 'file')
        fid2 = fopen(stubFile, 'w');
        fprintf(fid2, '%% placeholder\n');
        fclose(fid2);
    end
end

end
