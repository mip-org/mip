classdef TestUpdateAllAndDeps < matlab.unittest.TestCase
%TESTUPDATEALLANDDEPS   Tests for mip.update --all and --deps flags.
%
%   These tests verify the --all and --deps flags without requiring
%   network access. They use local source packages and fake installed
%   packages to test the expansion logic.

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_update_flags_test'];
            testCase.SourceDir = [tempname '_mip_src'];
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

        %% --- --all flag ---

        function testUpdateAll_UpdatesAllLocalPackages(testCase)
            % Install two local packages, update --all should reinstall both.
            srcA = createTestSourcePackage(testCase.SourceDir, 'pkgA');
            srcB = createTestSourcePackage(testCase.SourceDir, 'pkgB');
            mip.install(srcA);
            mip.install(srcB);

            pkgDirA = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'pkgA');
            pkgDirB = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'pkgB');
            infoA1 = mip.config.read_package_json(pkgDirA);
            infoB1 = mip.config.read_package_json(pkgDirB);

            pause(1.1);

            mip.update('--all');

            infoA2 = mip.config.read_package_json(pkgDirA);
            infoB2 = mip.config.read_package_json(pkgDirB);
            testCase.verifyFalse(strcmp(infoA2.timestamp, infoA1.timestamp), ...
                'pkgA should have been reinstalled');
            testCase.verifyFalse(strcmp(infoB2.timestamp, infoB1.timestamp), ...
                'pkgB should have been reinstalled');
        end

        function testUpdateAll_PreservesLoadState(testCase)
            % Install two packages, load one, update --all.
            % Loaded package should be reloaded, unloaded should stay unloaded.
            srcA = createTestSourcePackage(testCase.SourceDir, 'pkgA');
            srcB = createTestSourcePackage(testCase.SourceDir, 'pkgB');
            mip.install(srcA);
            mip.install(srcB);

            mip.load('local/local/pkgA');
            testCase.verifyTrue(mip.state.is_loaded('local/local/pkgA'));
            testCase.verifyFalse(mip.state.is_loaded('local/local/pkgB'));

            mip.update('--all');

            testCase.verifyTrue(mip.state.is_loaded('local/local/pkgA'), ...
                'pkgA should be reloaded after update --all');
            testCase.verifyFalse(mip.state.is_loaded('local/local/pkgB'), ...
                'pkgB should remain unloaded after update --all');
        end

        function testUpdateAll_ErrorsWithPackageNames(testCase)
            % --all cannot be combined with explicit package names.
            srcA = createTestSourcePackage(testCase.SourceDir, 'pkgA');
            mip.install(srcA);

            testCase.verifyError(@() mip.update('--all', 'local/local/pkgA'), ...
                'mip:update:allWithPackages');
        end

        function testUpdateAll_NoPackagesInstalled(testCase)
            % --all with no packages installed should print a message and return.
            mip.update('--all');
            % Should not error — just a no-op
        end

        function testUpdateAll_WithForce(testCase)
            % --all combined with --force should work.
            srcA = createTestSourcePackage(testCase.SourceDir, 'pkgA');
            mip.install(srcA);

            pkgDirA = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'pkgA');
            infoA1 = mip.config.read_package_json(pkgDirA);

            pause(1.1);

            mip.update('--all', '--force');

            infoA2 = mip.config.read_package_json(pkgDirA);
            testCase.verifyFalse(strcmp(infoA2.timestamp, infoA1.timestamp), ...
                'pkgA should have been reinstalled with --all --force');
        end

        %% --- --deps flag ---

        function testUpdateDeps_UpdatesPackageAndDependency(testCase)
            % Install a dependency, then a package that depends on it.
            % --deps should update both.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            mip.state.add_directly_installed('mip-org/core/depA');

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depA'});
            mip.install(srcMain);

            pkgDirMain = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            infoMain1 = mip.config.read_package_json(pkgDirMain);

            pause(1.1);

            mip.update('--deps', 'local/local/mypkg');

            infoMain2 = mip.config.read_package_json(pkgDirMain);
            testCase.verifyFalse(strcmp(infoMain2.timestamp, infoMain1.timestamp), ...
                'Main package should have been reinstalled with --deps');
        end

        function testUpdateDeps_PreservesLoadState(testCase)
            % Load a package with deps, update --deps, verify load state preserved.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            mip.state.add_directly_installed('mip-org/core/depA');

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depA'});
            mip.install(srcMain);

            mip.load('local/local/mypkg');
            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'));

            mip.update('--deps', 'local/local/mypkg');

            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'), ...
                'Main package should be reloaded after --deps update');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'), ...
                'Dependency should be reloaded after --deps update');
        end

        function testUpdateDeps_WithForce(testCase)
            % --deps combined with --force should work.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            mip.state.add_directly_installed('mip-org/core/depA');

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depA'});
            mip.install(srcMain);

            pkgDirMain = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            infoMain1 = mip.config.read_package_json(pkgDirMain);

            pause(1.1);

            mip.update('--deps', '--force', 'local/local/mypkg');

            infoMain2 = mip.config.read_package_json(pkgDirMain);
            testCase.verifyFalse(strcmp(infoMain2.timestamp, infoMain1.timestamp), ...
                'Main package should have been reinstalled with --deps --force');
        end

        function testUpdateDeps_SkipsUninstalledDeps(testCase)
            % If a package lists a dependency that is not installed,
            % --deps should not error — just skip it and let the normal
            % new-dependency step handle it later.
            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'nonexistent_dep'});
            mip.install(srcMain);

            pkgDirMain = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            infoMain1 = mip.config.read_package_json(pkgDirMain);

            pause(1.1);

            mip.update('--deps', 'local/local/mypkg');

            infoMain2 = mip.config.read_package_json(pkgDirMain);
            testCase.verifyFalse(strcmp(infoMain2.timestamp, infoMain1.timestamp), ...
                'Main package should still be reinstalled even if dep is missing');
        end

        function testUpdateDeps_TransitiveDeps(testCase)
            % depB depends on depC. mypkg depends on depB.
            % --deps should update mypkg, depB, and depC.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depC');
            mip.state.add_directly_installed('mip-org/core/depC');

            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depB', ...
                'dependencies', {'depC'});
            mip.state.add_directly_installed('mip-org/core/depB');

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depB'});
            mip.install(srcMain);

            mip.load('local/local/mypkg');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depC'));

            mip.update('--deps', 'local/local/mypkg');

            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'), ...
                'Main package should be reloaded');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depB'), ...
                'depB should be reloaded');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depC'), ...
                'depC (transitive) should be reloaded');
        end

    end
end
