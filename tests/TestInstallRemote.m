classdef TestInstallRemote < matlab.unittest.TestCase
%TESTINSTALLREMOTE   Integration tests for installing/loading packages
%   from remote channels (test-channel1, test-channel2).
%
%   These tests require network access to GitHub Pages.
%   Skipped in run_tests() when MIP_SKIP_REMOTE is set.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_channel_test'];
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

        %% --- Basic install from non-core channel ---

        function testInstallFromChannel_BareNameWithChannelFlag(testCase)
            % Install a package using --channel flag with bare name
            mip.install('--channel', 'mip-org/test-channel1', 'alpha');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should be installed at mip-org/test-channel1/alpha');
        end

        function testInstallFromChannel_FQN(testCase)
            % Install a package using fully qualified name
            mip.install('mip-org/test-channel2/beta');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'beta');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should be installed at mip-org/test-channel2/beta');
        end

        function testInstallFromChannel_SpecificVersion(testCase)
            % Install a specific version of a package
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should be installed');

            % Verify version in mip.json
            mipJson = fullfile(pkgDir, 'mip.json');
            pkgInfo = jsondecode(fileread(mipJson));
            testCase.verifyEqual(pkgInfo.version, '1.0.0', ...
                'Installed version should be 1.0.0');
        end

        %% --- Same-channel FQN dependency ---

        function testInstallFromChannel_SameChannelDep(testCase)
            % gamma depends on mip-org/test-channel1/alpha (FQN)
            mip.install('--channel', 'mip-org/test-channel1', 'gamma');

            gammaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'gamma');
            alphaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');

            testCase.verifyTrue(exist(gammaDir, 'dir') > 0, ...
                'gamma should be installed');
            testCase.verifyTrue(exist(alphaDir, 'dir') > 0, ...
                'alpha should be installed as dependency of gamma');
        end

        %% --- Cross-channel FQN dependency ---

        function testInstallFromChannel_CrossChannelDep(testCase)
            % cross (test-channel2) depends on mip-org/test-channel1/alpha
            mip.install('--channel', 'mip-org/test-channel2', 'cross');

            crossDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'cross');
            alphaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');

            testCase.verifyTrue(exist(crossDir, 'dir') > 0, ...
                'cross should be installed from test-channel2');
            testCase.verifyTrue(exist(alphaDir, 'dir') > 0, ...
                'alpha should be auto-installed from test-channel1 as dependency');
        end

        function testInstallFromChannel_CrossChannelDepPreInstalled(testCase)
            % Pre-install alpha, then install cross which depends on it
            mip.install('mip-org/test-channel1/alpha');
            mip.install('--channel', 'mip-org/test-channel2', 'cross');

            crossDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'cross');
            testCase.verifyTrue(exist(crossDir, 'dir') > 0, ...
                'cross should be installed');
        end

        %% --- Same name on different channels ---

        function testInstallFromChannel_SameNameDifferentChannels(testCase)
            % Install shared from both channels
            mip.install('--channel', 'mip-org/test-channel1', 'shared');
            mip.install('--channel', 'mip-org/test-channel2', 'shared');

            dir1 = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'shared');
            dir2 = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'shared');

            testCase.verifyTrue(exist(dir1, 'dir') > 0, ...
                'shared should be installed from test-channel1');
            testCase.verifyTrue(exist(dir2, 'dir') > 0, ...
                'shared should be installed from test-channel2');
        end

        %% --- Bare-name dependency resolving to core ---

        function testInstallFromChannel_BareNameDepToCore(testCase)
            % core_dep depends on 'chebfun' (bare name → mip-org/core)
            mip.install('--channel', 'mip-org/test-channel1', 'core_dep');

            coreDepDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'core_dep');
            chebfunDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'core', 'chebfun');

            testCase.verifyTrue(exist(coreDepDir, 'dir') > 0, ...
                'core_dep should be installed from test-channel1');
            testCase.verifyTrue(exist(chebfunDir, 'dir') > 0, ...
                'chebfun should be installed from core as bare-name dependency');
        end

        %% --- Load from non-core channel ---

        function testLoadFromChannel_Basic(testCase)
            % Install then load from non-core channel
            mip.install('mip-org/test-channel1/alpha');
            mip.load('mip-org/test-channel1/alpha');

            testCase.verifyTrue(mip.utils.is_loaded('mip-org/test-channel1/alpha'), ...
                'alpha should be loaded');
        end

        function testLoadFromChannel_FunctionAccessible(testCase)
            % Install, load, and verify function works
            mip.install('mip-org/test-channel1/alpha');
            mip.load('mip-org/test-channel1/alpha');

            result = alpha();
            testCase.verifyTrue(contains(result, 'from test-channel1'), ...
                'alpha function should return string identifying test-channel1');
        end

        %% --- Load with dependencies ---

        function testLoadFromChannel_WithSameChannelDep(testCase)
            % Install gamma (depends on alpha, same channel), then load
            mip.install('--channel', 'mip-org/test-channel1', 'gamma');
            mip.load('mip-org/test-channel1/gamma');

            testCase.verifyTrue(mip.utils.is_loaded('mip-org/test-channel1/gamma'), ...
                'gamma should be loaded');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/test-channel1/alpha'), ...
                'alpha should be loaded as dependency of gamma');
        end

        %% --- Load disambiguation (same name, multiple channels) ---

        function testLoadFromChannel_DisambiguateByFQN(testCase)
            % Install shared from both channels, load specific one
            mip.install('--channel', 'mip-org/test-channel1', 'shared');
            mip.install('--channel', 'mip-org/test-channel2', 'shared');

            mip.load('mip-org/test-channel1/shared');

            testCase.verifyTrue(mip.utils.is_loaded('mip-org/test-channel1/shared'), ...
                'test-channel1/shared should be loaded');

            result = shared();
            testCase.verifyTrue(contains(result, 'from test-channel1'), ...
                'shared function should return test-channel1 version');
        end

        %% --- Install already installed (idempotent) ---

        function testInstallFromChannel_AlreadyInstalled(testCase)
            % Installing same package twice should not error
            mip.install('mip-org/test-channel1/alpha');
            mip.install('mip-org/test-channel1/alpha');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should still be installed');
        end

    end

end
