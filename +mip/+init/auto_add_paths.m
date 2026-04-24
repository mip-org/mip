function [paths, extraPaths] = auto_add_paths(pkgDir)
%AUTO_ADD_PATHS   Heuristically determine which directories of a package
%should be added to the MATLAB path.
%
% Args:
%   pkgDir - Absolute or relative path to the package root directory.
%
% Returns:
%   paths      - Cell array of directory paths relative to pkgDir, in walk
%                order. The root itself is included as '.' if it contains
%                runtime .m files or a +namespace/@class/private folder.
%   extraPaths - Struct mapping group name ('tests', 'examples',
%                'benchmarks') to a cell array of directory paths for
%                top-level folders that look like that group. Used to
%                populate mip.yaml's `extra_paths` field.

pkgDir = char(pkgDir);
pkgDir = regexprep(pkgDir, '[/\\]+$', '');

% Directory names that should never be added to the path.
skipNames = { ...
    'doc', 'docs', 'documentation', 'man', ...
    'html', 'website', ...
    'build', 'buildutils', 'bin', 'obj', 'dist', 'target', ...
    'node_modules', '__pycache__', ...
    'paper', ...
    'dev', 'sandbox', 'scratch', ...
    '.git', '.github', '.svn', '.hg', '.circleci', '.vscode', '.idea'};

% Top-level directory names that route to extra_paths groups instead of
% the main paths list. Matching is case-insensitive and exact.
groupDirs = struct();
groupDirs.tests      = {'test', 'tests', 'testing', 'unittest', 'unittests'};
groupDirs.examples   = {'example', 'examples', 'demo', 'demos', ...
                        'tutorial', 'tutorials'};
groupDirs.benchmarks = {'benchmark', 'benchmarks'};

% Nested walks still skip group dirs so deeper copies (e.g. src/tests/)
% don't pollute any bucket.
allGroupNames = {};
for g = fieldnames(groupDirs)'
    allGroupNames = [allGroupNames, groupDirs.(g{1})]; %#ok<AGROW>
end
nestedSkip = [skipNames, allGroupNames];

paths = walk(pkgDir, pkgDir, nestedSkip, {});

groupPaths = struct();
entries = dir(pkgDir);
for k = 1:numel(entries)
    e = entries(k);
    if ~e.isdir, continue; end
    if strcmp(e.name, '.') || strcmp(e.name, '..'), continue; end
    nlow = lower(e.name);
    for g = fieldnames(groupDirs)'
        if any(strcmp(nlow, groupDirs.(g{1})))
            if ~isfield(groupPaths, g{1})
                groupPaths.(g{1}) = {};
            end
            groupPaths.(g{1}) = walk(pkgDir, fullfile(pkgDir, e.name), ...
                                     nestedSkip, groupPaths.(g{1}));
            break;
        end
    end
end

% De-duplicate while preserving order.
[~, idx] = unique(paths, 'stable');
paths = paths(idx);

extraPaths = struct();
for g = fieldnames(groupPaths)'
    collected = groupPaths.(g{1});
    if ~isempty(collected)
        [~, idx] = unique(collected, 'stable');
        extraPaths.(g{1}) = collected(idx);
    end
end

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
% script rather than a runtime library function. Note: Contents.m is
% treated as build-only since it contains only documentation comments;
% a directory whose only .m file is Contents.m will not be auto-added,
% which means `help <dirname>` won't resolve for that folder.
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
