function bundle_runtime_libs(mexFile)
%BUNDLE_RUNTIME_LIBS   Bundle a MEX file's dynamic library dependencies.
%
% Scans <mexFile>'s dynamic dependencies (NEEDED entries on Linux,
% LC_LOAD_DYLIB entries on macOS), filters out system and MATLAB-provided
% libraries, and for each remaining dynamic dep:
%   - Copies the library next to <mexFile> (via copy_and_sanitize_lib),
%     fixing SONAME / install_name to a relative form.
%   - Rewrites the referrer's reference so the bundled copy is loaded.
%   - Sets RPATH on the MEX so the bundled libs are found via $ORIGIN
%     (Linux) / @loader_path (macOS).
%
% Bundling is TRANSITIVE: after copying a third-party library it recurses
% into that library's own dynamic dependencies and bundles those too (and
% rewrites the copied library's references to its bundled siblings), so the
% packaged result is fully self-contained. It never descends into a system
% or MATLAB-provided library: those, and their whole dependency subtree, are
% resolved at runtime by the OS or by MATLAB and are never bundled (a second
% copy of, e.g., libstdc++/libgfortran would be shadowed by MATLAB's own and
% risks an ABI clash).
%
% "MATLAB-provided" is detected dynamically, identically on both platforms:
% a library is MATLAB's if MATLAB ships a file of that name in one of its
% runtime dirs -- matlabroot/{bin,sys/os,extern/bin}/<arch>. Those dirs are
% on MATLAB's library search path (ahead of the MEX's own RPATH), so a
% bundled copy would be shadowed anyway. This is why libgfortran, libquadmath,
% libstdc++, libtbb, libMatlabEngine, ... are left to MATLAB, while libgomp --
% which Linux MATLAB does NOT ship -- is bundled.
%
% The two platforms run the same iterative worklist (bundle_walk); only the
% small set of platform primitives (linux_ops / macos_ops) differs.
%
% The result is a self-contained .mex* that depends only on system libraries
% guaranteed by the OS and libraries MATLAB resolves itself.
%
% No-op on Windows.

if ~exist(mexFile, 'file')
    error('mip:bundleRuntimeLibs:notFound', ...
          'MEX file not found: %s', mexFile);
end

if isunix() && ~ismac()
    ops = linux_ops();
elseif ismac()
    ops = macos_ops();
else
    return;   % Windows: bundling of .mexw64 deps is not handled yet.
end

bundle_walk(mexFile, fileparts(mexFile), ops);

end

% =========================================================================
% Shared driver
% =========================================================================
function bundle_walk(mexFile, outDir, ops)
%BUNDLE_WALK   Iterative transitive bundler shared by all platforms.
%
% Walks the MEX's dependency graph, copying every non-provided library into
% OUTDIR, rewriting referrers to load the bundled copies, and finally setting
% the MEX's RPATH. Platform specifics are injected through OPS.

cleanup = ops.setup(mexFile); %#ok<NASGU>  % e.g. clear LD_LIBRARY_PATH (Linux)

% Each worklist node records the original on-disk file we read dependencies
% from (so @rpath/@loader_path resolve against the real source locations) and
% the file whose load commands we rewrite (the MEX, or a placed bundle copy).
work = {struct('orig', mexFile, 'rewrite', mexFile)};
bundled = containers.Map('KeyType', 'char', 'ValueType', 'logical');
anyBundled = false;

while ~isempty(work)
    node = work{end};
    work(end) = [];

    refs = ops.deps(node.orig);
    for i = 1:numel(refs)
        ref = refs{i};
        if ops.is_provided(ref)
            continue;
        end
        src = ops.resolve(ref, node.orig);
        if isempty(src)
            warning('mip:bundleRuntimeLibs:unresolved', ...
                    'Could not resolve %s (referenced by %s); skipping', ...
                    ref, node.orig);
            continue;
        end
        name = lib_basename(ref);

        % Point this referrer at the bundled copy. Done for every referrer so
        % diamond dependencies get rewritten even when the lib is copied once.
        % (No-op on Linux, where libs are found by SONAME via the RPATH.)
        ops.rewrite_ref(node.rewrite, ref, name);
        anyBundled = true;

        if ~isKey(bundled, name)
            bundled(name) = true;
            fprintf('Bundling %s\n', ref);
            mip.build.copy_and_sanitize_lib(src, outDir);
            work{end+1} = struct('orig', src, ...
                'rewrite', fullfile(outDir, name)); %#ok<AGROW>
        end
    end
end

if anyBundled
    ops.set_mex_rpath(mexFile);
end

end

% =========================================================================
% Linux primitives
% =========================================================================
function ops = linux_ops()

matlabNames = scan_matlab_libnames('glnxa64');
% glibc / loader core libraries the OS always provides (not under matlabroot).
osStems = { ...
    'libc.so', 'libm.so', 'libpthread.so', 'libdl.so', 'librt.so', ...
    'libresolv.so', 'libnsl.so', 'libutil.so', 'libcrypt.so', ...
    'libanl.so', 'libthread_db.so', 'libmvec.so', ...
    'ld-linux-x86-64.so', 'ld-linux.so', 'linux-vdso.so', 'linux-gate.so'};
lddMap = containers.Map('KeyType', 'char', 'ValueType', 'char');

ops = struct( ...
    'setup',         @setup, ...
    'deps',          @needed_entries, ...
    'is_provided',   @is_provided, ...
    'resolve',       @resolve, ...
    'rewrite_ref',   @rewrite_ref, ...
    'set_mex_rpath', @set_mex_rpath);

    function c = setup(mexFile)
        % MATLAB injects its own (older) libstdc++.so.6 into LD_LIBRARY_PATH;
        % patchelf is C++-linked against the system's newer libstdc++ and
        % aborts with "GLIBCXX_x.y.z not found" when MATLAB's takes
        % precedence. Clear LD_LIBRARY_PATH for the bundling, restore after.
        oldLD = getenv('LD_LIBRARY_PATH');
        c = onCleanup(@() setenv('LD_LIBRARY_PATH', oldLD));
        setenv('LD_LIBRARY_PATH', '');
        % ldd resolves the MEX's full transitive closure to absolute paths in
        % one shot; use it as the SONAME -> path lookup for every lib.
        lddMap = ldd_resolve(mexFile);
    end

    function tf = is_provided(soname)
        tf = any(strcmp(soname_stem(soname), osStems)) ...
          || any(strcmp(matlabNames, soname)) ...
          || any(startsWith(matlabNames, [soname '.']));
    end

    function p = resolve(soname, ~)
        if isKey(lddMap, soname)
            p = lddMap(soname);
        else
            p = '';
        end
    end

    function rewrite_ref(~, ~, ~)
        % No-op: Linux loads by SONAME, found via the $ORIGIN RPATH that
        % copy_and_sanitize_lib stamps on every copy and set_mex_rpath stamps
        % on the MEX.
    end

    function set_mex_rpath(mexFile)
        mip.build.echo_and_run(sprintf( ...
            'patchelf --set-rpath ''$ORIGIN'' "%s"', mexFile));
    end
end

% =========================================================================
% macOS primitives
% =========================================================================
function ops = macos_ops()

matlabNames = scan_matlab_libnames('maca64');

ops = struct( ...
    'setup',         @(~) [], ...
    'deps',          @otool_deps, ...
    'is_provided',   @is_provided, ...
    'resolve',       @resolve, ...
    'rewrite_ref',   @rewrite_ref, ...
    'set_mex_rpath', @set_mex_rpath);

    function tf = is_provided(instName)
        tf = startsWith(instName, '/usr/lib/') ...
          || startsWith(instName, '/System/Library/') ...
          || any(strcmp(matlabNames, lib_basename(instName)));
    end

    function p = resolve(instName, origPath)
        p = resolve_macos_dep(instName, origPath, otool_rpaths(origPath));
    end

    function rewrite_ref(file, instName, name)
        mip.build.echo_and_run(sprintf( ...
            'install_name_tool -change "%s" "@rpath/%s" "%s"', ...
            instName, name, file));
    end

    function set_mex_rpath(mexFile)
        [~, rpathOut] = system(sprintf('otool -l "%s"', mexFile));
        if isempty(regexp(rpathOut, 'path @loader_path\>', 'once'))
            mip.build.echo_and_run(sprintf( ...
                'install_name_tool -add_rpath @loader_path "%s"', mexFile));
        end
    end
end

% =========================================================================
% Shared helpers
% =========================================================================
function name = lib_basename(ref)
% Basename of a SONAME or install name. 'libgomp.so.1' -> 'libgomp.so.1';
% '@rpath/libfoo.dylib' -> 'libfoo.dylib'.
[~, b, e] = fileparts(ref);
name = [b e];
end

function names = scan_matlab_libnames(arch)
% File names of every library MATLAB ships for ARCH, across its runtime dirs.
subdirs = { ...
    fullfile('bin', arch), ...
    fullfile('sys', 'os', arch), ...
    fullfile('extern', 'bin', arch)};
names = {};
for i = 1:numel(subdirs)
    d = dir(fullfile(matlabroot, subdirs{i}));
    if isempty(d); continue; end
    d = d(~[d.isdir]);
    names = [names, {d.name}]; %#ok<AGROW>
end
end

% --- Linux (ELF) ---------------------------------------------------------
function needed = needed_entries(file)
% DT_NEEDED SONAMEs of an ELF file, in link order.
[~, out] = system(sprintf('readelf -d "%s"', file));
tok = regexp(out, '\(NEEDED\)\s+Shared library: \[([^\]]+)\]', 'tokens');
needed = cellfun(@(c) c{1}, tok, 'UniformOutput', false);
end

function resolved = ldd_resolve(file)
% Map SONAME -> absolute path for FILE's full transitive closure.
[~, out] = system(sprintf('ldd "%s"', file));
m = regexp(out, '(\S+)\s+=>\s+(/\S+)', 'tokens');
resolved = containers.Map('KeyType', 'char', 'ValueType', 'char');
for i = 1:numel(m)
    if ~isKey(resolved, m{i}{1})
        resolved(m{i}{1}) = m{i}{2};
    end
end
end

function stem = soname_stem(soname)
% Strip the version suffix: 'libc.so.6' -> 'libc.so',
% 'ld-linux-x86-64.so.2' -> 'ld-linux-x86-64.so'.
t = regexp(soname, '^(.*?\.so)', 'tokens', 'once');
if isempty(t)
    stem = soname;
else
    stem = t{1};
end
end

% --- macOS (Mach-O) ------------------------------------------------------
function deps = otool_deps(file)
% LC_LOAD_DYLIB install names of a Mach-O file, excluding its own id.
[~, out] = system(sprintf('otool -L "%s"', file));
lines = splitlines(out);
deps = {};
for i = 2:numel(lines)   % line 1 is "<file>:"
    line = strtrim(lines{i});
    if isempty(line); continue; end
    t = regexp(line, '^(\S+)', 'tokens', 'once');
    if isempty(t); continue; end
    deps{end+1} = t{1}; %#ok<AGROW>
end
selfId = otool_id(file);   % a dylib lists its own id; a MEX bundle has none
if ~isempty(selfId)
    deps = deps(~strcmp(deps, selfId));
end
end

function id = otool_id(file)
% Install id (LC_ID_DYLIB) of a Mach-O file, or '' if it has none.
[~, out] = system(sprintf('otool -D "%s"', file));
lines = splitlines(strtrim(out));
if numel(lines) >= 2
    id = strtrim(lines{2});
else
    id = '';
end
end

function rpaths = otool_rpaths(file)
% LC_RPATH search paths of a Mach-O file.
[~, out] = system(sprintf('otool -l "%s"', file));
m = regexp(out, 'path (\S+) \(offset \d+\)', 'tokens');
rpaths = cellfun(@(c) c{1}, m, 'UniformOutput', false);
end

function p = resolve_macos_dep(instName, refFile, rpaths)
% Resolve a Mach-O dependency install name to an absolute on-disk path,
% returning '' when it cannot be located (e.g. @executable_path).
p = '';
refDir = fileparts(refFile);

if startsWith(instName, '/')
    if exist(instName, 'file'); p = instName; end
    return;
end
if startsWith(instName, '@loader_path/')
    cand = fullfile(refDir, extractAfter(instName, '@loader_path/'));
    if exist(cand, 'file'); p = cand; end
    return;
end
if startsWith(instName, '@rpath/')
    name = extractAfter(instName, '@rpath/');
    for i = 1:numel(rpaths)
        base = rpaths{i};
        if startsWith(base, '@loader_path')
            base = fullfile(refDir, extractAfter(base, '@loader_path'));
        elseif startsWith(base, '@executable_path')
            continue;   % anchored to the host executable; not resolvable
        end
        cand = fullfile(base, name);
        if exist(cand, 'file'); p = cand; return; end
    end
    return;
end
% @executable_path/... or a bare/relative name: not resolvable for bundling.
end
