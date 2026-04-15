function paths = auto_add_paths(pkgDir)
%AUTO_ADD_PATHS   Heuristically determine which directories of a package
%should be added to the MATLAB path.
%
% Args:
%   pkgDir - Absolute or relative path to the package root directory.
%
% Returns:
%   paths - Cell array of directory paths relative to pkgDir, in walk
%           order. The root itself is included as '.' if it contains
%           runtime .m files or a +namespace/@class/private folder.

pkgDir = char(pkgDir);
pkgDir = regexprep(pkgDir, '[/\\]+$', '');

% Directory names that should never be added to the path.
skipNames = { ...
    'test', 'tests', 'testing', 'unittest', 'unittests', ...
    'demo', 'demos', ...
    'example', 'examples', 'tutorial', 'tutorials', ...
    'benchmark', 'benchmarks', ...
    'doc', 'docs', 'documentation', 'man', ...
    'html', 'website', ...
    'build', 'buildutils', 'bin', 'obj', 'dist', 'target', ...
    'node_modules', '__pycache__', ...
    'paper', ...
    'dev', 'sandbox', 'scratch', ...
    '.git', '.github', '.svn', '.hg', '.circleci', '.vscode', '.idea'};

paths = {};
paths = walk(pkgDir, pkgDir, skipNames, paths);

% De-duplicate while preserving order.
[~, idx] = unique(paths, 'stable');
paths = paths(idx);

end


function paths = walk(root, dirPath, skipNames, paths)
entries = dir(dirPath);

mFiles = {};
hasSpecial = false;  % @class / +namespace / private subfolder
for k = 1:numel(entries)
    e = entries(k);
    if e.isdir
        if is_namespace_or_class(e.name)
            hasSpecial = true;
        elseif strcmpi(e.name, 'private')
            hasSpecial = true;
        end
    else
        [~, ~, ext] = fileparts(e.name);
        if strcmpi(ext, '.m')
            mFiles{end+1} = e.name; %#ok<AGROW>
        elseif ~isempty(regexpi(ext, '^\.mex[^.]*$', 'once'))
            mFiles{end+1} = e.name; %#ok<AGROW>
        end
    end
end

include = hasSpecial || ~isempty(mFiles);

% Filter out directories whose only .m files are development / build
% scripts (buildfile.m, createMLTBX.m, *_dev.m, install.m, setup.m).
% If that filter empties the .m list and there's no special folder, skip.
if include && ~hasSpecial
    keep = false;
    for k = 1:numel(mFiles)
        if ~is_build_only_script(mFiles{k})
            keep = true;
            break;
        end
    end
    include = keep;
end

if include
    paths{end+1} = relpath(root, dirPath); %#ok<AGROW>
end

for k = 1:numel(entries)
    e = entries(k);
    if ~e.isdir, continue; end
    if strcmp(e.name, '.') || strcmp(e.name, '..'), continue; end
    if is_namespace_or_class(e.name), continue; end
    if strcmpi(e.name, 'private'), continue; end
    if any(strcmpi(e.name, skipNames)), continue; end
    if is_skip_prefix(e.name), continue; end
    if is_platform_dir(e.name), continue; end
    paths = walk(root, fullfile(dirPath, e.name), skipNames, paths);
end
end


function tf = is_build_only_script(name)
% Return true if the filename looks like a build / install / dev
% script rather than a runtime library function.
[~, base, ~] = fileparts(name);
baseL = lower(base);
exact = {'buildfile', 'build', 'make', 'makefile', ...
         'install', 'setup', 'uninstall', ...
         'createmltbx', 'packagetoolbox', 'contents'};
if any(strcmp(baseL, exact))
    tf = true; return;
end
patterns = {'_dev$', '_install$', '_setup$', '_build$', ...
            '^install_', '^setup_', '^build_', ...
            '^compile', '^mex_compile', '^make_'};
for k = 1:numel(patterns)
    if ~isempty(regexp(baseL, patterns{k}, 'once'))
        tf = true; return;
    end
end
tf = false;
end


function tf = is_namespace_or_class(name)
% A directory name qualifies as a MATLAB namespace (+foo) or class
% folder (@foo) only if the part after the sigil is a legal MATLAB
% identifier.
if ~startsWith(name, '+') && ~startsWith(name, '@')
    tf = false; return;
end
inner = name(2:end);
tf = ~isempty(regexp(inner, '^[A-Za-z][A-Za-z0-9_]*$', 'once'));
end


function tf = is_skip_prefix(name)
prefixes = {'example', 'demo', 'tutorial', 'benchmark', 'sandbox'};
nlow = lower(name);
for k = 1:numel(prefixes)
    if startsWith(nlow, prefixes{k})
        tf = true; return;
    end
end
tf = false;
end


function tf = is_platform_dir(name)
% Directories named after a build target / OS-arch that hold prebuilt
% binaries. Users pick one via a loader or copy its contents into
% `private/`; they do NOT addpath it.
nlow = lower(name);
exact = {'glnxa64', 'glnx86', 'maci', 'maci64', 'maca64', ...
         'pcwin', 'pcwin32', 'pcwin64', 'win32', 'win64', ...
         'sol2', 'mingw32', 'mingw64'};
if any(strcmp(nlow, exact))
    tf = true; return;
end
patterns = {'^darwin[-_]', '^linux[-_]', '^gnu-linux[-_]?', ...
            '^mac[-_]', '^macos[-_]', '^mingw[0-9]*[-_]', ...
            '^win[-_]', '^win32[-_]', '^win64[-_]', ...
            '^freebsd[-_]', '^cygwin[-_]'};
for k = 1:numel(patterns)
    if ~isempty(regexp(nlow, patterns{k}, 'once'))
        tf = true; return;
    end
end
tf = false;
end


function r = relpath(root, p)
if strcmp(root, p)
    r = '.';
    return;
end
r = p(numel(root)+1:end);
r = regexprep(r, '^[/\\]+', '');
r = strrep(r, '\', '/');
end
