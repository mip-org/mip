classdef TestLoadAddpathRmpath < matlab.unittest.TestCase
%TESTLOADADDPATHRMPATH   Tests for `mip load --addpath` / `--rmpath`
% and the post-unload defensive path sweep.

    properties
        OrigMipRoot
        TestRoot
        SavedPath
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_addpath_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.SavedPath = path;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            % Restore path before any test-introduced entries vanish with
            % the temp dir (otherwise stale entries can confuse later tests).
            path(testCase.SavedPath);
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        %% --- Flag parsing / validation ---

        function testAddpath_MissingValue_Errors(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            testCase.verifyError(@() mip.load('foo', '--addpath'), ...
                'mip:missingFlagValue');
        end

        function testRmpath_MissingValue_Errors(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            testCase.verifyError(@() mip.load('foo', '--rmpath'), ...
                'mip:missingFlagValue');
        end

        function testAddpath_MultiplePackages_Errors(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'bar');
            testCase.verifyError( ...
                @() mip.load('foo', 'bar', '--addpath', 'src'), ...
                'mip:load:addpathSinglePackage');
        end

        function testRmpath_MultiplePackages_Errors(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'bar');
            testCase.verifyError( ...
                @() mip.load('foo', 'bar', '--rmpath', 'src'), ...
                'mip:load:addpathSinglePackage');
        end

        %% --- Apply --addpath ---

        function testAddpath_AddsSourceRelativePath(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'src/extra'});
            mip.load('foo', '--addpath', 'src/extra');
            expected = fullfile(pkgDir, 'foo', 'src', 'extra');
            testCase.verifyTrue(onPath(expected), ...
                sprintf('expected %s on path', expected));
        end

        function testAddpath_MultipleFlagsAccumulate(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'src/a', 'src/b'});
            mip.load('foo', '--addpath', 'src/a', '--addpath', 'src/b');
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'src', 'a')));
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'src', 'b')));
        end

        function testAddpath_MissingDirWarns(testCase)
            % Rely on MATLAB's native addpath warning rather than a custom one.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            testCase.verifyWarning( ...
                @() mip.load('foo', '--addpath', 'does/not/exist'), ...
                'MATLAB:mpath:nameNonexistentOrNotADirectory');
        end

        function testAddpath_AppliesToAlreadyLoaded(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'src/extra'});
            mip.load('foo');
            % Now adjust the path on the already-loaded package
            mip.load('foo', '--addpath', 'src/extra');
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'src', 'extra')));
        end

        %% --- Apply --rmpath ---

        function testRmpath_RemovesPreLoadedPath(testCase)
            % `--rmpath .` removes the package source subdir from the path
            % after load has addpath'd it.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            sourceSubdir = fullfile(pkgDir, 'foo');
            mip.load('foo', '--rmpath', '.');
            testCase.verifyFalse(onPath(sourceSubdir), ...
                '--rmpath should remove the source-relative target');
        end

        function testRmpath_NotOnPath_WarnsFromMatlab(testCase)
            % --rmpath of a target that is not currently on the search path
            % surfaces MATLAB's native rmpath warning. This pins the
            % documented behavior (rmpath warns rather than errors).
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'src/extra'});
            testCase.verifyWarning( ...
                @() mip.load('foo', '--rmpath', 'src/extra'), ...
                'MATLAB:rmpath:DirNotFound');
        end

        %% --- Unload sweep ---

        function testUnload_SweepsAddpathEntries(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'src/extra'});
            mip.load('foo', '--addpath', 'src/extra');
            target = fullfile(pkgDir, 'foo', 'src', 'extra');
            testCase.verifyTrue(onPath(target));

            mip.unload('foo');
            testCase.verifyFalse(onPath(target), ...
                'unload sweep should remove --addpath entries');
        end

        function testUnload_DoesNotTouchUnrelatedSiblingPaths(testCase)
            % Create a sibling directory whose name shares a prefix with
            % the package source dir. The sweep must not touch it.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            sourceSubdir = fullfile(pkgDir, 'foo');
            siblingDir = [sourceSubdir '_sibling'];
            mkdir(siblingDir);
            addpath(siblingDir);

            mip.load('foo');
            mip.unload('foo');

            testCase.verifyTrue(onPath(siblingDir), ...
                'sweep must not remove sibling path with shared prefix');
        end

        %% --- --addpath does NOT propagate to dependencies ---

        function testAddpath_NotAppliedToDependencies(testCase)
            % Dep `dep1` has a src/extra dir. Main package depends on dep1.
            % Loading the main package with --addpath src/extra should
            % NOT addpath the dep's src/extra.
            depDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'dep1', ...
                'subdirs', {'src/extra'});
            mainDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'main', ...
                'subdirs', {'src/extra'}, ...
                'dependencies', {'dep1'});

            mip.load('main', '--addpath', 'src/extra');

            mainTarget = fullfile(mainDir, 'main', 'src', 'extra');
            depTarget = fullfile(depDir, 'dep1', 'src', 'extra');
            testCase.verifyTrue(onPath(mainTarget), ...
                '--addpath should apply to the named package');
            testCase.verifyFalse(onPath(depTarget), ...
                '--addpath must not propagate to dependencies');
        end

    end
end


function tf = onPath(p)
    tf = ismember(p, strsplit(path, pathsep));
end
