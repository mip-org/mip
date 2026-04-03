classdef TestUpdatePackage < matlab.unittest.TestCase
%TESTUPDATEPACKAGE   Tests for mip.update mechanics.
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

        function testUpdateNotInstalled_ErrorsBareNam(testCase)
            testCase.verifyError(@() mip.update('nonexistent'), ...
                'mip:update:notInstalled');
        end

        function testUpdateNotInstalled_ErrorsFQN(testCase)
            testCase.verifyError(@() mip.update('mip-org/core/nonexistent'), ...
                'mip:update:notInstalled');
        end

        %% --- Local package: source_path stored ---

        function testCopyInstall_StoresSourcePath(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'source_path'), ...
                'Non-editable local install should store source_path in mip.json');
            testCase.verifyTrue(contains(info.source_path, testCase.SourceDir), ...
                'source_path should point to original source directory');
        end

        function testEditableInstall_StoresSourcePath(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'source_path'));
            testCase.verifyTrue(contains(info.source_path, testCase.SourceDir));
        end

        %% --- Local package update always reinstalls ---

        function testUpdateLocalPackage_AlwaysReinstalls(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'version', '1.0.0');
            mip.utils.install_local(srcDir, false);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info1 = mip.utils.read_package_json(pkgDir);
            timestamp1 = info1.timestamp;

            % Small pause to ensure timestamp changes
            pause(1.1);

            % Update — should reinstall even though version hasn't changed
            mip.update('local/local/mypkg');

            info2 = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should still be installed after update');
            testCase.verifyFalse(strcmp(info2.timestamp, timestamp1), ...
                'Timestamp should change after reinstall');
        end

        function testUpdateLocalPackage_EditableReinstalls(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info1 = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(info1.editable, 'Should be editable');

            pause(1.1);

            mip.update('local/local/mypkg');

            info2 = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(info2.editable, ...
                'Should still be editable after update');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);
        end

        %% --- Load state preserved across update ---

        function testUpdateLocalPackage_PreservesLoadState(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

            % Load the package
            mip.load('local/local/mypkg');
            testCase.verifyTrue(mip.utils.is_loaded('local/local/mypkg'));

            % Update
            mip.update('local/local/mypkg');

            % Should be reloaded
            testCase.verifyTrue(mip.utils.is_loaded('local/local/mypkg'), ...
                'Package should be reloaded after update');
        end

        function testUpdateLocalPackage_UnloadedStaysUnloaded(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

            % Don't load — just update
            testCase.verifyFalse(mip.utils.is_loaded('local/local/mypkg'));

            mip.update('local/local/mypkg');

            testCase.verifyFalse(mip.utils.is_loaded('local/local/mypkg'), ...
                'Package should remain unloaded if it was not loaded before update');
        end

        %% --- Local update errors ---

        function testUpdateLocalPackage_MissingSourceErrors(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

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
            mip.utils.install_local(srcDir, false);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info1 = mip.utils.read_package_json(pkgDir);

            pause(1.1);

            % Update using bare name
            mip.update('mypkg');

            info2 = mip.utils.read_package_json(pkgDir);
            testCase.verifyFalse(strcmp(info2.timestamp, info1.timestamp), ...
                'Bare name update should work and reinstall');
        end

        %% --- Directly installed tracking ---

        function testUpdateLocalPackage_PreservesDirectlyInstalled(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

            testCase.verifyTrue(ismember('local/local/mypkg', ...
                mip.utils.get_directly_installed()));

            mip.update('local/local/mypkg');

            testCase.verifyTrue(ismember('local/local/mypkg', ...
                mip.utils.get_directly_installed()), ...
                'Package should still be directly installed after update');
        end

    end
end
