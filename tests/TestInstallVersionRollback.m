classdef TestInstallVersionRollback < matlab.unittest.TestCase
%TESTINSTALLVERSIONROLLBACK   Issue #232: `mip install foo@v2` must not
%   destroy the installed copy of foo before the new download succeeds.
%
%   Uses a synthetic channel index whose mhl_url points at an unreachable
%   host, so downloadAndInstall always fails. The test then verifies that
%   the previously-installed version is still present on disk and still
%   tracked as directly installed.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_versionrollback_test'];
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

        function testVersionReplace_DownloadFailureRestoresOldVersion(testCase)
            % Pre-install foo@1.0.0 and mark it directly installed.
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'foo', ...
                'version', '1.0.0');
            mip.state.add_directly_installed('mylab/custom/foo');

            % Synthetic channel index advertising foo@2.0.0 with a bad URL.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/custom', { ...
                struct('name', 'foo', 'version', '2.0.0', ...
                       'mhl_url', 'https://example.invalid/foo-2.0.0.mhl')});

            % The install must fail (download cannot succeed)...
            testCase.verifyError( ...
                @() mip.install('mylab/custom/foo@2.0.0'), ...
                ?MException);

            % ...and the old installation must be intact.
            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mylab', 'custom', 'foo');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'foo pkgDir should be restored after failed @version replace');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.version, '1.0.0', ...
                'Restored foo should be the original 1.0.0, not 2.0.0');
            testCase.verifyTrue(ismember('gh/mylab/custom/foo', ...
                mip.state.get_directly_installed()), ...
                'foo should still be directly installed after rollback');
        end

    end
end
