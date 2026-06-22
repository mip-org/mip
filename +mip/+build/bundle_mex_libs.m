function bundle_mex_libs(pkgDir)
%BUNDLE_MEX_LIBS   Vendor runtime-library dependencies for compiled MEX files.
%
% After a package's compile script runs, each MEX file it produced may depend
% on non-system shared libraries (e.g. libgfortran, libgomp) that are not
% guaranteed to exist on end-user machines. This scans <pkgDir> (recursively)
% for compiled MEX files and bundles those dependencies next to each one so the
% packaged result is self-contained.
%
% The platform-specific bundling is delegated to `bundle_runtime_libs`, which
% is provided by the channel build environment -- the build workflow adds
% mip_channel_tools/scripts to the MATLAB path. When that function is not on
% the path (e.g. a standalone `mip bundle` outside a channel build), this is a
% no-op, so the package manager carries no hard dependency on the channel
% tooling. This is the counterpart to the pre-compile strip_prebuilt_binaries
% step: strip stale binaries before, vendor freshly built ones after.

if exist('bundle_runtime_libs', 'file') ~= 2
    return
end

mexFiles = dir(fullfile(pkgDir, '**', '*.mex*'));
mexFiles = mexFiles(~[mexFiles.isdir]);
for i = 1:numel(mexFiles)
    bundle_runtime_libs(fullfile(mexFiles(i).folder, mexFiles(i).name));
end

end
