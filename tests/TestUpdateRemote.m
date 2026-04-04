classdef TestUpdateRemote < matlab.unittest.TestCase
%TESTUPDATEREMOTE   Integration tests for mip.update with remote channels.
%
%   These tests require network access to GitHub Pages.
%   Skipped in run_tests() when MIP_SKIP_REMOTE is set.
%
%   Uses test-channel1 (alpha 1.0.0 and 2.0.0) to test version upgrades.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_remote_update_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        %% --- Version upgrade ---

        function testUpdate_UpgradesVersion(testCase)
            % Install alpha@1.0.0, then update should upgrade to 2.0.0
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info1 = mip.utils.read_package_json(pkgDir);
            testCase.verifyEqual(info1.version, '1.0.0');

            mip.update('mip-org/test-channel1/alpha');

            info2 = mip.utils.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, '2.0.0', ...
                'Update should upgrade alpha from 1.0.0 to 2.0.0');
        end

        %% --- Already up to date ---

        function testUpdate_AlreadyUpToDate(testCase)
            % Install latest alpha (2.0.0), update should be a no-op
            mip.install('mip-org/test-channel1/alpha');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info1 = mip.utils.read_package_json(pkgDir);
            testCase.verifyEqual(info1.version, '2.0.0');

            mip.update('mip-org/test-channel1/alpha');

            info2 = mip.utils.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, '2.0.0');
            testCase.verifyEqual(info2.timestamp, info1.timestamp, ...
                'Timestamp should not change when already up to date');
        end

        %% --- Force update ---

        function testUpdate_ForceReinstallsLatest(testCase)
            % Install latest alpha, force update should reinstall
            mip.install('mip-org/test-channel1/alpha');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');

            % Drop a marker file; if force update reinstalls, it will be gone
            marker = fullfile(pkgDir, '.test_marker');
            fid = fopen(marker, 'w'); fclose(fid);
            testCase.verifyTrue(exist(marker, 'file') > 0);

            mip.update('--force', 'mip-org/test-channel1/alpha');

            info2 = mip.utils.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, '2.0.0');
            testCase.verifyFalse(exist(marker, 'file') > 0, ...
                'Marker file should be gone after force reinstall');
        end

        %% --- Load state preserved ---

        function testUpdate_PreservesLoadState(testCase)
            % Install old version, load, update, verify still loaded
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');
            mip.load('mip-org/test-channel1/alpha');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/test-channel1/alpha'));

            mip.update('mip-org/test-channel1/alpha');

            testCase.verifyTrue(mip.utils.is_loaded('mip-org/test-channel1/alpha'), ...
                'Package should be reloaded after update');

            info = mip.utils.read_package_json(fullfile(testCase.TestRoot, ...
                'packages', 'mip-org', 'test-channel1', 'alpha'));
            testCase.verifyEqual(info.version, '2.0.0', ...
                'Should be upgraded to latest version');
        end

        function testUpdate_PreservesUnloadState(testCase)
            % Install old version without loading, update, verify still unloaded
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/test-channel1/alpha'));

            mip.update('mip-org/test-channel1/alpha');

            testCase.verifyFalse(mip.utils.is_loaded('mip-org/test-channel1/alpha'), ...
                'Package should remain unloaded if it was not loaded before update');

            info = mip.utils.read_package_json(fullfile(testCase.TestRoot, ...
                'packages', 'mip-org', 'test-channel1', 'alpha'));
            testCase.verifyEqual(info.version, '2.0.0', ...
                'Should be upgraded to latest version');
        end

    end
end
