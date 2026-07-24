function mipSourceDir = plantStubMip(pkgDir)
%PLANTSTUBMIP   Make a seeded gh/mip-org/core/mip look like the running mip.
%
% The self flows (self-uninstall and the self-update/install hot swap)
% only trigger when the active root's mip package is the mip that is
% actually running — mip.self.is_own_root compares the directory of
% which('mip') against the package's source directory. Tests that
% exercise the self flows against an isolated MIP_ROOT call this to
% plant a stub mip.m in the seeded package's source directory and put
% that directory at the front of the MATLAB path, so which('mip')
% resolves there. The package-qualified mip.* functions still run from
% the repo.
%
% Callers must remove the path entry in teardown (cleanupTestPaths on
% the test root covers it).
%
% Args:
%   pkgDir - The seeded package directory (from createTestPackage)
%
% Returns:
%   mipSourceDir - The stub source directory that was added to the path

mipSourceDir = fullfile(pkgDir, 'mip');
if ~exist(mipSourceDir, 'dir')
    mkdir(mipSourceDir);
end
fid = fopen(fullfile(mipSourceDir, 'mip.m'), 'w');
fprintf(fid, 'function varargout = mip(varargin) %%#ok<STOUT,VANUS>\nend\n');
fclose(fid);
addpath(mipSourceDir);

end
