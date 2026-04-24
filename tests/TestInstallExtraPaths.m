classdef TestInstallExtraPaths < matlab.unittest.TestCase
%TESTINSTALLEXTRAPATHS   Install-time tests for the extra_paths field.
%
% Covers how prepare_package / install_local resolve extra_paths in
% mip.yaml into the concrete list written to mip.json -- in particular
% the recursive: true and exclude: options, which delegate to
% mip.build.compute_addpaths under the hood.

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_extras_test'];
            testCase.SourceDir = [tempname '_mip_extras_src'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            if exist(testCase.SourceDir, 'dir')
                rmdir(testCase.SourceDir, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testExtraPaths_PlainEntry_LandsInMipJson(testCase)
            % A single plain entry under extra_paths.examples should
            % be written to mip.json as a one-element list under the
            % same group name.
            extras = struct('examples', {{struct('path', 'examples')}});
            createTestSourcePackage(testCase.SourceDir, 'pkg_plain', ...
                'extraPaths', extras, 'subdirs', {'examples'});

            mip.install('-e', fullfile(testCase.SourceDir, 'pkg_plain'));

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'pkg_plain');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'extra_paths'));
            testCase.verifyTrue(isfield(info.extra_paths, 'examples'));
            testCase.verifyEqual(info.extra_paths.examples, {'examples'});
        end

        function testExtraPaths_Recursive_WalksSubdirs(testCase)
            % recursive: true on an extra_paths entry should walk the
            % directory and include every subdir that contains runtime
            % .m files -- same as the top-level `paths:` behavior.
            entry = struct('path', 'examples', 'recursive', true);
            extras = struct('examples', {{entry}});
            createTestSourcePackage(testCase.SourceDir, 'pkg_recursive', ...
                'extraPaths', extras, ...
                'subdirs', {'examples', 'examples/advanced', 'examples/utils'});

            mip.install('-e', fullfile(testCase.SourceDir, 'pkg_recursive'));

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'pkg_recursive');
            info = mip.config.read_package_json(pkgDir);
            resolved = info.extra_paths.examples;
            testCase.verifyTrue(ismember('examples', resolved));
            testCase.verifyTrue(ismember(fullfile('examples', 'advanced'), resolved));
            testCase.verifyTrue(ismember(fullfile('examples', 'utils'), resolved));
        end

        function testExtraPaths_RecursiveWithExclude_SkipsNamedDirs(testCase)
            % exclude: [...] under a recursive entry filters the walk.
            % The excluded dir (and anything beneath it) must not
            % appear in the resolved list.
            entry = struct('path', 'examples', 'recursive', true, ...
                           'exclude', {{'internal'}});
            extras = struct('examples', {{entry}});
            createTestSourcePackage(testCase.SourceDir, 'pkg_exclude', ...
                'extraPaths', extras, ...
                'subdirs', {'examples', 'examples/keep', ...
                            'examples/internal', 'examples/internal/nested'});

            mip.install('-e', fullfile(testCase.SourceDir, 'pkg_exclude'));

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'pkg_exclude');
            info = mip.config.read_package_json(pkgDir);
            resolved = info.extra_paths.examples;
            testCase.verifyTrue(ismember('examples', resolved));
            testCase.verifyTrue(ismember(fullfile('examples', 'keep'), resolved));
            testCase.verifyFalse(ismember(fullfile('examples', 'internal'), resolved), ...
                'excluded dir should not appear in resolved list');
            testCase.verifyFalse(ismember(fullfile('examples', 'internal', 'nested'), resolved), ...
                'dirs beneath an excluded dir should not appear either');
        end

        function testExtraPaths_LoadAppliesResolvedList(testCase)
            % End-to-end: install a package with recursive extras, then
            % load with --with examples, and verify each resolved dir
            % lands on the MATLAB path.
            entry = struct('path', 'examples', 'recursive', true);
            extras = struct('examples', {{entry}});
            srcDir = createTestSourcePackage(testCase.SourceDir, 'pkg_e2e', ...
                'extraPaths', extras, ...
                'subdirs', {'examples', 'examples/advanced'});

            savedPath = path;
            restorePath = onCleanup(@() path(savedPath));

            mip.install('-e', srcDir);
            mip.load('pkg_e2e', '--with', 'examples');

            testCase.verifyTrue(onPath(fullfile(srcDir, 'examples')));
            testCase.verifyTrue(onPath(fullfile(srcDir, 'examples', 'advanced')));
            clear restorePath;
        end

    end
end


function tf = onPath(p)
    tf = ismember(p, strsplit(path, pathsep));
end
