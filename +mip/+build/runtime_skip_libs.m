function [linuxSonames, macPrefixes] = runtime_skip_libs()
%RUNTIME_SKIP_LIBS   Libraries bundle_runtime_libs must never vendor.
%
% Returns the deny-lists used when scanning a MEX's dynamic dependencies:
%   linuxSonames - exact SONAMEs (Linux NEEDED entries) to skip.
%   macPrefixes  - install-path prefixes (macOS LC_LOAD_DYLIB) to skip.
%
% Two classes of library are skipped:
%   1. OS-guaranteed system libraries (libc, libm, the loader, libstdc++, ...).
%   2. Libraries MATLAB itself provides and resolves at runtime via its own
%      library path -- libmx/libmex/libmat/..., and the MATLAB BLAS/LAPACK
%      (libmwblas/libmwlapack). These must NOT be vendored: on Linux they are
%      simply unresolvable at bundle time (MATLAB clears them off the loader
%      path), and on macOS their LC_LOAD_DYLIB is `@rpath/libmwblas.dylib`,
%      which has no on-disk path to copy -- so bundling them would either warn
%      and skip (Linux) or hard-fail the copy (macOS). MATLAB always ships
%      them, so the MEX finds them at load time regardless.
%
% libgfortran.so.5 is skipped on Linux: MATLAB ships it on its own loader path
% (searched before the MEX's $ORIGIN rpath) and the build toolchain is pinned
% so our symbol requirements stay within MATLAB's copy. libgomp is deliberately
% NOT skipped: Linux MATLAB does not ship it, so its bundled copy is load-bearing.

linuxSonames = { ...
    'linux-vdso.so.1', 'ld-linux-x86-64.so.2', ...
    'libc.so.6', 'libm.so.6', 'libpthread.so.0', 'libdl.so.2', 'librt.so.1', ...
    'libstdc++.so.6', 'libgcc_s.so.1', 'libgfortran.so.5', ...
    'libmx.so', 'libmex.so', 'libmat.so', ...
    'libmwblas.so', 'libmwlapack.so', ...
    'libMatlabDataArray.so', 'libMatlabEngine.so'};

macPrefixes = { ...
    '/usr/lib/', ...
    '/System/Library/', ...
    '@rpath/libmx.', '@rpath/libmex.', '@rpath/libmat.', ...
    '@rpath/libmwblas.', '@rpath/libmwlapack.', ...
    '@rpath/libMatlabDataArray.', '@rpath/libMatlabEngine.'};

end
