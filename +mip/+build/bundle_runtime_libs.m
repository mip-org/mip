function bundle_runtime_libs(mexFile)
%BUNDLE_RUNTIME_LIBS   Bundle a MEX file's dynamic library dependencies.
%
% Scans <mexFile>'s dynamic dependencies (NEEDED entries on Linux,
% LC_LOAD_DYLIB entries on macOS), filters out system and MATLAB-provided
% libraries, and for each remaining dynamic dep:
%   - Copies the library next to <mexFile> (via copy_and_sanitize_lib),
%     fixing SONAME / install_name to a relative form.
%   - Rewrites the MEX's own reference so the bundled copy is loaded.
%   - Sets RPATH on the MEX so the bundled libs are found via $ORIGIN
%     (Linux) / @loader_path (macOS).
%
% The result is a self-contained .mex* that depends only on system libraries
% guaranteed by the OS and libraries MATLAB resolves itself.
%
% No-op on Windows.
%
% Bundling is deliberately NON-recursive: it scans only the MEX's own NEEDED
% entries, not the NEEDED entries of the libs it copies. This is intentional,
% not a bug — a bundled lib's transitive deps (e.g. libgfortran -> libquadmath,
% libz) are expected to be provided at runtime by the OS or by MATLAB. Add
% recursion only if a genuinely third-party transitive dep ever appears.

if ~exist(mexFile, 'file')
    error('mip:bundleRuntimeLibs:notFound', ...
          'MEX file not found: %s', mexFile);
end

outDir = fileparts(mexFile);

if isunix() && ~ismac()
    bundle_linux(mexFile, outDir);
elseif ismac
    bundle_macos(mexFile, outDir);
end

end

% -------------------------------------------------------------------------
function bundle_linux(mexFile, outDir)

% MATLAB injects its own (older) libstdc++.so.6 into LD_LIBRARY_PATH;
% patchelf is C++-linked against the system's newer libstdc++ and
% aborts with "GLIBCXX_x.y.z not found" when MATLAB's takes precedence.
% Clear LD_LIBRARY_PATH for the duration of this function.
oldLD = getenv('LD_LIBRARY_PATH');
restorer = onCleanup(@() setenv('LD_LIBRARY_PATH', oldLD)); %#ok<NASGU>
setenv('LD_LIBRARY_PATH', '');

% Parse NEEDED entries.
[~, out] = system(sprintf('readelf -d "%s"', mexFile));
tok = regexp(out, '\(NEEDED\)\s+Shared library: \[([^\]]+)\]', 'tokens');
needed = cellfun(@(c) c{1}, tok, 'UniformOutput', false);

% Resolve NEEDED to absolute paths via ldd.
[~, out] = system(sprintf('ldd "%s"', mexFile));
m = regexp(out, '(\S+)\s+=>\s+(/\S+)', 'tokens');
resolved = containers.Map('KeyType', 'char', 'ValueType', 'char');
for i = 1:numel(m)
    resolved(m{i}{1}) = m{i}{2};
end

skip = linux_skip_set();
bundled = false;
for i = 1:numel(needed)
    so = needed{i};
    if any(strcmp(so, skip))
        continue;
    end
    if ~isKey(resolved, so)
        warning('mip:bundleRuntimeLibs:unresolved', ...
                'Could not resolve %s via ldd; skipping', so);
        continue;
    end
    fprintf('Bundling %s\n', so);
    mip.build.copy_and_sanitize_lib(resolved(so), outDir);
    bundled = true;
end

if bundled
    mip.build.echo_and_run(sprintf( ...
        'patchelf --set-rpath ''$ORIGIN'' "%s"', mexFile));
end

end

% -------------------------------------------------------------------------
function bundle_macos(mexFile, outDir)

[~, out] = system(sprintf('otool -L "%s"', mexFile));
lines = splitlines(out);
skipPats = macos_skip_patterns();
bundled = false;
% Line 1 is "<mexFile>:" — skip.
for i = 2:numel(lines)
    line = strtrim(lines{i});
    if isempty(line); continue; end
    t = regexp(line, '^(\S+)', 'tokens', 'once');
    if isempty(t); continue; end
    libPath = t{1};
    if any(cellfun(@(p) startsWith(libPath, p), skipPats))
        continue;
    end
    fprintf('Bundling %s\n', libPath);
    mip.build.copy_and_sanitize_lib(libPath, outDir);
    [~, base, ext] = fileparts(libPath);
    libName = [base ext];
    mip.build.echo_and_run(sprintf( ...
        'install_name_tool -change "%s" "@rpath/%s" "%s"', ...
        libPath, libName, mexFile));
    bundled = true;
end

if bundled
    % Add @loader_path rpath if not already present.
    [~, rpathOut] = system(sprintf('otool -l "%s"', mexFile));
    if isempty(regexp(rpathOut, 'path @loader_path', 'once'))
        mip.build.echo_and_run(sprintf( ...
            'install_name_tool -add_rpath @loader_path "%s"', mexFile));
    end
end

end

% -------------------------------------------------------------------------
function s = linux_skip_set()
% SONAMEs we never bundle: OS-guaranteed system libs, and libs MATLAB
% resolves at runtime via its own LD_LIBRARY_PATH (sys/os/glnxa64).
%
% libgfortran.so.5 is skipped: Linux MATLAB ships it, it is on MATLAB's
% LD_LIBRARY_PATH (searched before the MEX's $ORIGIN RPATH), and the build
% toolchain is pinned so our symbol requirements stay within MATLAB's copy.
% libgomp is deliberately NOT here: Linux MATLAB does NOT ship it, so its
% bundled copy is load-bearing.
s = { ...
    'linux-vdso.so.1', 'ld-linux-x86-64.so.2', ...
    'libc.so.6', 'libm.so.6', 'libpthread.so.0', 'libdl.so.2', 'librt.so.1', ...
    'libstdc++.so.6', 'libgcc_s.so.1', 'libgfortran.so.5', ...
    'libmx.so', 'libmex.so', 'libmat.so', ...
    'libMatlabDataArray.so', 'libMatlabEngine.so'};
end

function s = macos_skip_patterns()
% Path prefixes we never bundle: OS framework / system libs, and any dylib
% MATLAB resolves via @rpath in its own rpath chain.
s = { ...
    '/usr/lib/', ...
    '/System/Library/', ...
    '@rpath/libmx.', '@rpath/libmex.', '@rpath/libmat.', ...
    '@rpath/libMatlabDataArray.', '@rpath/libMatlabEngine.'};
end
