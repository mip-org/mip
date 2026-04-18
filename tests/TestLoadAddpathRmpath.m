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
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            testCase.verifyError(@() mip.load('foo', '--addpath'), ...
                'mip:load:missingAddpathValue');
        end

        function testRmpath_MissingValue_Errors(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            testCase.verifyError(@() mip.load('foo', '--rmpath'), ...
                'mip:load:missingRmpathValue');
        end

        function testAddpath_MultiplePackages_Errors(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'bar', ...
                'sourceSubdir', true);
            testCase.verifyError( ...
                @() mip.load('foo', 'bar', '--addpath', 'src'), ...
                'mip:load:addpathSinglePackage');
        end

        function testRmpath_MultiplePackages_Errors(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'bar', ...
                'sourceSubdir', true);
            testCase.verifyError( ...
                @() mip.load('foo', 'bar', '--rmpath', 'src'), ...
                'mip:load:addpathSinglePackage');
        end

        %% --- Apply --addpath ---

        function testAddpath_AddsSourceRelativePath(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true, 'subdirs', {'src/extra'});
            mip.load('foo', '--addpath', 'src/extra');
            expected = fullfile(pkgDir, 'foo', 'src', 'extra');
            testCase.verifyTrue(onPath(expected), ...
                sprintf('expected %s on path', expected));
        end

        function testAddpath_MultipleFlagsAccumulate(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true, 'subdirs', {'src/a', 'src/b'});
            mip.load('foo', '--addpath', 'src/a', '--addpath', 'src/b');
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'src', 'a')));
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'src', 'b')));
        end

        function testAddpath_MissingDirWarns(testCase)
            % Rely on MATLAB's native addpath warning rather than a custom one.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            testCase.verifyWarning( ...
                @() mip.load('foo', '--addpath', 'does/not/exist'), ...
                'MATLAB:mpath:nameNonexistentOrNotADirectory');
        end

        function testAddpath_AppliesToAlreadyLoaded(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true, 'subdirs', {'src/extra'});
            mip.load('foo');
            % Now adjust the path on the already-loaded package
            mip.load('foo', '--addpath', 'src/extra');
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'src', 'extra')));
        end

        %% --- Apply --rmpath ---

        function testRmpath_RemovesPreLoadedPath(testCase)
            % load_package.m adds pkg_dir/foo; --rmpath . removes the
            % source subdir if it was on the path.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            sourceSubdir = fullfile(pkgDir, 'foo');
            addpath(sourceSubdir);
            testCase.verifyTrue(onPath(sourceSubdir));
            mip.load('foo', '--rmpath', '.');
            testCase.verifyFalse(onPath(sourceSubdir), ...
                '--rmpath should remove the source-relative target');
        end

        function testRmpath_NotOnPath_WarnsFromMatlab(testCase)
            % --rmpath of a target that is not currently on the search path
            % surfaces MATLAB's native rmpath warning. This pins the
            % documented behavior (rmpath warns rather than errors).
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true, 'subdirs', {'src/extra'});
            testCase.verifyWarning( ...
                @() mip.load('foo', '--rmpath', 'src/extra'), ...
                'MATLAB:rmpath:DirNotFound');
        end

        %% --- Unload sweep ---

        function testUnload_SweepsAddpathEntries(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true, 'subdirs', {'src/extra'});
            mip.load('foo', '--addpath', 'src/extra');
            target = fullfile(pkgDir, 'foo', 'src', 'extra');
            testCase.verifyTrue(onPath(target));

            mip.unload('foo');
            testCase.verifyFalse(onPath(target), ...
                'unload sweep should remove --addpath entries');
        end

        function testUnload_SweepsResidualEntriesFromStaleUnloadScript(testCase)
            % Build a package where load_package.m adds a path but
            % unload_package.m DOES NOT remove it. The sweep should still
            % clean it up.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            sourceSubdir = fullfile(pkgDir, 'foo');
            % Replace unload_package.m with a no-op
            fid = fopen(fullfile(pkgDir, 'unload_package.m'), 'w');
            fprintf(fid, 'function unload_package()\nend\n');
            fclose(fid);

            mip.load('foo');
            testCase.verifyTrue(onPath(sourceSubdir), ...
                'load_package.m should have added the source subdir');

            mip.unload('foo');
            testCase.verifyFalse(onPath(sourceSubdir), ...
                'sweep should remove the residual entry');
        end

        function testUnload_SweepsWhenUnloadScriptMissing(testCase)
            % When unload_package.m does not exist, mip:unloadNotFound
            % fires AND the sweep still cleans up the path entry that
            % load_package.m added.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
            sourceSubdir = fullfile(pkgDir, 'foo');
            delete(fullfile(pkgDir, 'unload_package.m'));

            mip.load('foo');
            testCase.verifyTrue(onPath(sourceSubdir));

            testCase.verifyWarning(@() mip.unload('foo'), 'mip:unloadNotFound');
            testCase.verifyFalse(onPath(sourceSubdir), ...
                'sweep should run even when unload_package.m is absent');
        end

        function testUnload_DoesNotTouchUnrelatedSiblingPaths(testCase)
            % Create a sibling directory whose name shares a prefix with
            % the package source dir. The sweep must not touch it.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'sourceSubdir', true);
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
                'sourceSubdir', true, 'subdirs', {'src/extra'});
            mainDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'main', ...
                'sourceSubdir', true, 'subdirs', {'src/extra'}, ...
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
