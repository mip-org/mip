classdef TestUpdateLocal < matlab.unittest.TestCase
%TESTUPDATELOCAL   Tests for mip.update mechanics.
%
%   These tests verify the update flow without requiring network access.
%   They test:
%     - Local package updates always reinstall
%     - Load state is preserved across updates
%     - Errors on non-installed packages
%     - source_path is stored for local installs (both editable and copy)

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_update_test'];
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

        %% --- Error cases ---

        function testUpdateNotInstalled_ErrorsBareName(testCase)
            testCase.verifyError(@() mip.update('nonexistent'), ...
                'mip:update:notInstalled');
        end

        function testUpdateNotInstalled_ErrorsFQN(testCase)
            testCase.verifyError(@() mip.update('mip-org/core/nonexistent'), ...
                'mip:update:notInstalled');
        end

        %% --- Local package update always reinstalls ---

        function testUpdateLocalPackage_AlwaysReinstalls(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'version', '1.0.0');
            mip.install(srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info1 = mip.config.read_package_json(pkgDir);
            timestamp1 = info1.timestamp;

            % Small pause to ensure timestamp changes
            pause(1.1);

            % Update — should reinstall even though version hasn't changed
            mip.update('local/local/mypkg');

            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should still be installed after update');
            testCase.verifyFalse(strcmp(info2.timestamp, timestamp1), ...
                'Timestamp should change after reinstall');
        end

        function testUpdateLocalPackage_EditableReinstalls(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info1 = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(info1.editable, 'Should be editable');

            pause(1.1);

            mip.update('local/local/mypkg');

            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(info2.editable, ...
                'Should still be editable after update');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);
        end

        function testUpdateLocalPackage_EditableRerunsCompileScript(testCase)
            % Editable update should re-run the compile_script (issue #103).
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'compile.m');
            mip.install('-e', srcDir);

            % Compile script writes a .compiled marker into the source dir
            markerPath = fullfile(srcDir, '.compiled');
            testCase.verifyTrue(exist(markerPath, 'file') > 0, ...
                'compile_script should run on initial install');

            % Delete the marker, then update
            delete(markerPath);
            testCase.verifyFalse(exist(markerPath, 'file') > 0);

            mip.update('local/local/mypkg');

            testCase.verifyTrue(exist(markerPath, 'file') > 0, ...
                'compile_script should run again on update');
        end

        function testUpdateLocalPackage_NoCompileFlagNotPreserved(testCase)
            % `mip install -e --no-compile` followed by `mip update` should
            % run the compile_script -- the original --no-compile flag is
            % not preserved across updates (issue #103).
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'compile.m');
            mip.install('-e', srcDir, '--no-compile');

            markerPath = fullfile(srcDir, '.compiled');
            testCase.verifyFalse(exist(markerPath, 'file') > 0, ...
                'compile_script should NOT run with --no-compile');

            mip.update('local/local/mypkg');

            testCase.verifyTrue(exist(markerPath, 'file') > 0, ...
                'compile_script should run on update even though original install used --no-compile');
        end

        %% --- Load state preserved across update ---

        function testUpdateLocalPackage_PreservesLoadState(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            % Load the package
            mip.load('local/local/mypkg');
            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'));

            % Update
            mip.update('local/local/mypkg');

            % Should be reloaded
            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'), ...
                'Package should be reloaded after update');
        end

        function testUpdateLocalPackage_UnloadedStaysUnloaded(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            % Don't load — just update
            testCase.verifyFalse(mip.state.is_loaded('local/local/mypkg'));

            mip.update('local/local/mypkg');

            testCase.verifyFalse(mip.state.is_loaded('local/local/mypkg'), ...
                'Package should remain unloaded if it was not loaded before update');
        end

        %% --- Local update errors ---

        function testUpdateLocalPackage_MissingSourceErrors(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            % Remove the source directory
            rmdir(srcDir, 's');

            testCase.verifyError(@() mip.update('local/local/mypkg'), ...
                'mip:update:sourceNotFound');
        end

        function testUpdateLocalPackage_NoSourcePathErrors(testCase)
            % Create a local package without source_path in mip.json
            pkgDir = createTestPackage(testCase.TestRoot, 'local', 'local', 'oldpkg');
            % The createTestPackage helper doesn't add source_path

            testCase.verifyError(@() mip.update('local/local/oldpkg'), ...
                'mip:update:noSourcePath');
        end

        %% --- Bare name resolution ---

        function testUpdateLocalPackage_BareNameResolution(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info1 = mip.config.read_package_json(pkgDir);

            pause(1.1);

            % Update using bare name
            mip.update('mypkg');

            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyFalse(strcmp(info2.timestamp, info1.timestamp), ...
                'Bare name update should work and reinstall');
        end

        %% --- Directly installed tracking ---

        function testUpdateLocalPackage_PreservesDirectlyInstalled(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            testCase.verifyTrue(ismember('local/local/mypkg', ...
                mip.state.get_directly_installed()));

            mip.update('local/local/mypkg');

            testCase.verifyTrue(ismember('local/local/mypkg', ...
                mip.state.get_directly_installed()), ...
                'Package should still be directly installed after update');
        end

        %% --- Dependency + load state preservation ---

        function testUpdate_ReloadsDependencyAfterUpdate(testCase)
            % Install a dependency (fake installed package), then a local
            % source package that depends on it. Load the main package
            % (which transitively loads the dep). Update the main package
            % and verify both are still loaded afterward.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            mip.state.add_directly_installed('mip-org/core/depA');

            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depA'});
            mip.install(srcDir);

            mip.load('local/local/mypkg');
            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'), ...
                'depA should be transitively loaded');

            mip.update('local/local/mypkg');

            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'), ...
                'Main package should be reloaded after update');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'), ...
                'Dependency should still be loaded after update');
        end

        function testUpdate_PreservesDirectlyLoadedDistinction(testCase)
            % A package loaded only as a transitive dep should not be
            % promoted to directly loaded after update.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            mip.state.add_directly_installed('mip-org/core/depA');

            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depA'});
            mip.install(srcDir);

            mip.load('local/local/mypkg');

            % depA should be transitively loaded (not directly loaded)
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'));
            testCase.verifyFalse(mip.state.is_directly_loaded('mip-org/core/depA'), ...
                'depA should only be transitively loaded before update');

            mip.update('local/local/mypkg');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'));
            testCase.verifyFalse(mip.state.is_directly_loaded('mip-org/core/depA'), ...
                'depA should remain transitively loaded (not promoted to directly loaded)');
            testCase.verifyTrue(mip.state.is_directly_loaded('local/local/mypkg'), ...
                'Main package should remain directly loaded');
        end

        function testUpdate_MultiplePackages(testCase)
            % Updating multiple local packages at once should work.
            srcA = createTestSourcePackage(testCase.SourceDir, 'pkgA');
            srcB = createTestSourcePackage(testCase.SourceDir, 'pkgB');
            mip.install(srcA);
            mip.install(srcB);

            mip.load('local/local/pkgA');
            mip.load('local/local/pkgB');
            testCase.verifyTrue(mip.state.is_loaded('local/local/pkgA'));
            testCase.verifyTrue(mip.state.is_loaded('local/local/pkgB'));

            pkgDirA = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'pkgA');
            pkgDirB = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'pkgB');
            infoA1 = mip.config.read_package_json(pkgDirA);
            infoB1 = mip.config.read_package_json(pkgDirB);

            pause(1.1);

            mip.update('local/local/pkgA', 'local/local/pkgB');

            testCase.verifyTrue(mip.state.is_loaded('local/local/pkgA'), ...
                'pkgA should be reloaded');
            testCase.verifyTrue(mip.state.is_loaded('local/local/pkgB'), ...
                'pkgB should be reloaded');

            infoA2 = mip.config.read_package_json(pkgDirA);
            infoB2 = mip.config.read_package_json(pkgDirB);
            testCase.verifyFalse(strcmp(infoA2.timestamp, infoA1.timestamp), ...
                'pkgA should have been reinstalled');
            testCase.verifyFalse(strcmp(infoB2.timestamp, infoB1.timestamp), ...
                'pkgB should have been reinstalled');
        end

        %% --- --all flag ---

        function testUpdateAll_UpdatesAllLocalPackages(testCase)
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
            srcA = createTestSourcePackage(testCase.SourceDir, 'pkgA');
            mip.install(srcA);

            testCase.verifyError(@() mip.update('--all', 'local/local/pkgA'), ...
                'mip:update:allWithPackages');
        end

        function testUpdateAll_NoPackagesInstalled(testCase)
            mip.update('--all');
            % Should not error — just a no-op
        end

        function testUpdateAll_WithForce(testCase)
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
            srcDep = createTestSourcePackage(testCase.SourceDir, 'depA');
            mip.install(srcDep);

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'local/local/depA'});
            mip.install(srcMain);

            pkgDirMain = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            pkgDirDep = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'depA');
            infoMain1 = mip.config.read_package_json(pkgDirMain);
            infoDep1 = mip.config.read_package_json(pkgDirDep);

            pause(1.1);

            mip.update('--deps', 'local/local/mypkg');

            infoMain2 = mip.config.read_package_json(pkgDirMain);
            infoDep2 = mip.config.read_package_json(pkgDirDep);
            testCase.verifyFalse(strcmp(infoMain2.timestamp, infoMain1.timestamp), ...
                'Main package should have been reinstalled with --deps');
            testCase.verifyFalse(strcmp(infoDep2.timestamp, infoDep1.timestamp), ...
                'Dependency should have been reinstalled with --deps');
        end

        function testUpdateDeps_PreservesLoadState(testCase)
            srcDep = createTestSourcePackage(testCase.SourceDir, 'depA');
            mip.install(srcDep);

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'local/local/depA'});
            mip.install(srcMain);

            mip.load('local/local/mypkg');
            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'));
            testCase.verifyTrue(mip.state.is_loaded('local/local/depA'));

            mip.update('--deps', 'local/local/mypkg');

            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'), ...
                'Main package should be reloaded after --deps update');
            testCase.verifyTrue(mip.state.is_loaded('local/local/depA'), ...
                'Dependency should be reloaded after --deps update');
        end

        function testUpdateDeps_WithForce(testCase)
            srcDep = createTestSourcePackage(testCase.SourceDir, 'depA');
            mip.install(srcDep);

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'local/local/depA'});
            mip.install(srcMain);

            pkgDirMain = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            infoMain1 = mip.config.read_package_json(pkgDirMain);

            pause(1.1);

            mip.update('--deps', '--force', 'local/local/mypkg');

            infoMain2 = mip.config.read_package_json(pkgDirMain);
            testCase.verifyFalse(strcmp(infoMain2.timestamp, infoMain1.timestamp), ...
                'Main package should have been reinstalled with --deps --force');
        end

        function testUpdateDeps_TransitiveDeps(testCase)
            % depB depends on depC. mypkg depends on depB.
            % --deps should update mypkg, depB, and depC.
            srcC = createTestSourcePackage(testCase.SourceDir, 'depC');
            mip.install(srcC);

            srcB = createTestSourcePackage(testCase.SourceDir, 'depB', ...
                'dependencies', {'local/local/depC'});
            mip.install(srcB);

            srcMain = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'local/local/depB'});
            mip.install(srcMain);

            mip.load('local/local/mypkg');
            testCase.verifyTrue(mip.state.is_loaded('local/local/depC'));

            mip.update('--deps', 'local/local/mypkg');

            testCase.verifyTrue(mip.state.is_loaded('local/local/mypkg'), ...
                'Main package should be reloaded');
            testCase.verifyTrue(mip.state.is_loaded('local/local/depB'), ...
                'depB should be reloaded');
            testCase.verifyTrue(mip.state.is_loaded('local/local/depC'), ...
                'depC (transitive) should be reloaded');
        end

    end
end
