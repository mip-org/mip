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

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/alpha'), ...
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

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/gamma'), ...
                'gamma should be loaded');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/alpha'), ...
                'alpha should be loaded as dependency of gamma');
        end

        %% --- Load disambiguation (same name, multiple channels) ---

        function testLoadFromChannel_DisambiguateByFQN(testCase)
            % Install shared from both channels, load specific one
            mip.install('--channel', 'mip-org/test-channel1', 'shared');
            mip.install('--channel', 'mip-org/test-channel2', 'shared');

            mip.load('mip-org/test-channel1/shared');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/shared'), ...
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

        %% --- @version upgrade behavior (issue #102) ---

        function testInstallFromChannel_VersionUpgradeReplacesInstalled(testCase)
            % Install alpha@1.0.0, then mip install alpha@2.0.0 should
            % silently replace the installed version with the requested one.
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info1 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info1.version, '1.0.0');

            mip.install('--channel', 'mip-org/test-channel1', 'alpha@2.0.0');

            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, '2.0.0', ...
                'alpha should be upgraded to the requested version');
        end

        function testInstallFromChannel_VersionDowngradeReplacesInstalled(testCase)
            % Install alpha@2.0.0, then mip install alpha@1.0.0 should
            % silently replace it (downgrade is also a "replace").
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@2.0.0');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info1 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info1.version, '2.0.0');

            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');

            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, '1.0.0', ...
                'alpha should be downgraded to the requested version');
        end

        function testInstallFromChannel_SameVersionStaysInstalled(testCase)
            % Installing the same @version twice is idempotent (no replace).
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info1 = mip.config.read_package_json(pkgDir);
            timestamp1 = info1.timestamp;

            pause(1.1);

            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');

            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, '1.0.0');
            testCase.verifyEqual(info2.timestamp, timestamp1, ...
                'Same @version should not trigger reinstall');
        end

        function testInstallFromChannel_NoVersionDoesNotUpgrade(testCase)
            % Without an explicit @version, the existing "already installed"
            % behavior wins -- mip install does not auto-upgrade.
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info1 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info1.version, '1.0.0');

            % No @version -- alpha 2.0.0 is the channel's best version,
            % but we should NOT auto-upgrade.
            mip.install('--channel', 'mip-org/test-channel1', 'alpha');

            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, '1.0.0', ...
                'mip install pkg (no @version) should not upgrade');
        end

        function testInstallFromChannel_FQNVersionConstraintHonored(testCase)
            % FQN with @version pointing to a non-primary channel must
            % install the requested version, not the channel's best version.
            % Regression test: requestedVersions used to be name-keyed and
            % only applied to the primary channel index fetch, so this
            % silently installed the channel's default best version.
            mip.install('mip-org/test-channel1/alpha@1.0.0');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.version, '1.0.0', ...
                'FQN @version should reach the FQN''s channel');
        end

        function testInstallFromChannel_FQNVersionConstraintNotFoundErrors(testCase)
            % If the requested @version doesn't exist in the FQN's channel,
            % mip:versionNotFound should be raised (not silently fall through
            % to the best version).
            testCase.verifyError(@() ...
                mip.install('mip-org/test-channel1/alpha@99.99.99'), ...
                'mip:versionNotFound');
        end

        function testInstallFromChannel_VersionUpgradePreservesLoadState(testCase)
            % If the package was loaded before the upgrade, it should be
            % reloaded after the new version is installed.
            mip.install('--channel', 'mip-org/test-channel1', 'alpha@1.0.0');
            mip.load('mip-org/test-channel1/alpha');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/alpha'));

            mip.install('--channel', 'mip-org/test-channel1', 'alpha@2.0.0');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/alpha'), ...
                'alpha should be reloaded after the @version replace');
            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.version, '2.0.0');
        end

        %% --- --channel + FQN interaction (issue #105) ---

        function testInstallFromChannel_FQNIgnoresChannelFlag(testCase)
            % FQN takes precedence over --channel; the package should be
            % installed in the FQN's channel, not the --channel value.
            mip.install('--channel', 'mip-org/test-channel2', ...
                        'mip-org/test-channel1/alpha');

            installedDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            wrongDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'alpha');

            testCase.verifyTrue(exist(installedDir, 'dir') > 0, ...
                'alpha should be installed in test-channel1 (from FQN)');
            testCase.verifyFalse(exist(wrongDir, 'dir') > 0, ...
                'alpha should NOT be installed in test-channel2 (--channel ignored)');
        end

        function testInstallFromChannel_FQNOnlySkipsSpuriousFetch(testCase)
            % When all args are FQNs, --channel is ignored entirely --
            % including its index fetch. Pointing --channel at a
            % nonexistent channel must NOT cause an error.
            mip.install('--channel', 'nonexistent-org/nonexistent-channel', ...
                        'mip-org/test-channel1/alpha');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'alpha should be installed even with bogus --channel');
        end

        function testInstallFromChannel_MixedFQNAndBareUsesChannelForBare(testCase)
            % Mixed call: --channel applies to the bare-name arg,
            % FQN arg uses its own channel.
            mip.install('--channel', 'mip-org/test-channel1', ...
                        'alpha', 'mip-org/test-channel2/beta');

            alphaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            betaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'beta');

            testCase.verifyTrue(exist(alphaDir, 'dir') > 0, ...
                'bare-name alpha should be installed from --channel value');
            testCase.verifyTrue(exist(betaDir, 'dir') > 0, ...
                'FQN beta should be installed from its own channel');
        end

        %% --- Bare-name vs local directory dispatch (issue #107) ---

        function testInstall_BareNamePrefersChannelOverLocalDir(testCase)
            % If a directory with the same name exists in the cwd, a bare
            % name should still install from the channel -- not as a local
            % directory install.
            scratch = [tempname '_mip_cwd'];
            mkdir(scratch);
            cleanupScratch = onCleanup(@() rmdir(scratch, 's'));
            origCwd = pwd;
            cleanupCwd = onCleanup(@() cd(origCwd));
            cd(scratch);

            % Create a local 'alpha/' directory with a valid mip.yaml that
            % would otherwise have been picked up by the old behavior.
            localAlpha = fullfile(scratch, 'alpha');
            mkdir(localAlpha);
            fid = fopen(fullfile(localAlpha, 'mip.yaml'), 'w');
            fprintf(fid, 'name: alpha\nversion: "9.9.9"\naddpaths:\n  - path: "."\nbuilds:\n  - architectures: [any]\n');
            fclose(fid);

            mip.install('--channel', 'mip-org/test-channel1', 'alpha');

            channelDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            localPkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'local', 'local', 'alpha');

            testCase.verifyTrue(exist(channelDir, 'dir') > 0, ...
                'alpha should be installed from test-channel1');
            testCase.verifyFalse(exist(localPkgDir, 'dir') > 0, ...
                'alpha should NOT be installed as a local package');

            % Keep cleanup objects alive until end of test
            assert(isobject(cleanupScratch) && isobject(cleanupCwd));
        end

        function testInstall_BareNameFailureMentionsLocalDirHint(testCase)
            % If the channel install fails AND a directory with the bare
            % name exists in cwd, the error message should hint at './name'.
            scratch = [tempname '_mip_cwd'];
            mkdir(scratch);
            cleanupScratch = onCleanup(@() rmdir(scratch, 's'));
            origCwd = pwd;
            cleanupCwd = onCleanup(@() cd(origCwd));
            cd(scratch);

            % Create a local 'no_such_pkg_xyz/' directory in cwd
            mkdir(fullfile(scratch, 'no_such_pkg_xyz'));

            try
                mip.install('no_such_pkg_xyz');
                testCase.verifyFail('Expected mip.install to fail');
            catch ME
                testCase.verifyTrue(contains(ME.message, './no_such_pkg_xyz'), ...
                    'Error message should hint at ./no_such_pkg_xyz');
            end

            assert(isobject(cleanupScratch) && isobject(cleanupCwd));
        end

        function testInstall_BareNameWithVersionFailureMentionsLocalDirHint(testCase)
            % If 'foo@1.0' fails on the channel and a directory named 'foo'
            % exists in cwd, the error should hint at './foo'.
            scratch = [tempname '_mip_cwd'];
            mkdir(scratch);
            cleanupScratch = onCleanup(@() rmdir(scratch, 's'));
            origCwd = pwd;
            cleanupCwd = onCleanup(@() cd(origCwd));
            cd(scratch);

            mkdir(fullfile(scratch, 'no_such_pkg_xyz'));

            try
                mip.install('no_such_pkg_xyz@1.0');
                testCase.verifyFail('Expected mip.install to fail');
            catch ME
                testCase.verifyTrue(contains(ME.message, './no_such_pkg_xyz'), ...
                    'Error message should hint at ./no_such_pkg_xyz when @version is stripped');
            end

            assert(isobject(cleanupScratch) && isobject(cleanupCwd));
        end

        function testInstall_BareNameWithVersionFailureHintsLiteralAtDir(testCase)
            % If 'foo@1.0' fails on the channel and both 'foo@1.0' and
            % 'foo' exist as directories, the hint should prefer the exact
            % match 'foo@1.0'.
            scratch = [tempname '_mip_cwd'];
            mkdir(scratch);
            cleanupScratch = onCleanup(@() rmdir(scratch, 's'));
            origCwd = pwd;
            cleanupCwd = onCleanup(@() cd(origCwd));
            cd(scratch);

            mkdir(fullfile(scratch, 'no_such_pkg_xyz'));
            mkdir(fullfile(scratch, 'no_such_pkg_xyz@1.0'));

            try
                mip.install('no_such_pkg_xyz@1.0');
                testCase.verifyFail('Expected mip.install to fail');
            catch ME
                testCase.verifyTrue(contains(ME.message, './no_such_pkg_xyz@1.0'), ...
                    'Error message should hint at ./no_such_pkg_xyz@1.0 (exact match preferred)');
            end

            assert(isobject(cleanupScratch) && isobject(cleanupCwd));
        end

    end

end
