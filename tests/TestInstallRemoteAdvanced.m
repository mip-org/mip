classdef TestInstallRemoteAdvanced < matlab.unittest.TestCase
%TESTINSTALLREMOTEADVANCED   Advanced integration tests for remote install,
%   load, unload, and uninstall with complex dependency graphs.
%
%   Requires test-channel1 packages: chain_end, chain_mid, chain_top,
%   delta, with_test.
%   Requires test-channel2 packages: multi_dep, diamond_left,
%   diamond_right, diamond_top.
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
            testCase.TestRoot = [tempname '_mip_adv_test'];
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

        %% === Chained transitive dependencies (3 levels) ===

        function testInstall_ChainedDeps_AllInstalled(testCase)
            % chain_top -> chain_mid -> chain_end (3-level chain)
            mip.install('mip-org/test-channel1/chain_top');

            topDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_top');
            midDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_mid');
            endDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_end');

            testCase.verifyTrue(exist(topDir, 'dir') > 0, ...
                'chain_top should be installed');
            testCase.verifyTrue(exist(midDir, 'dir') > 0, ...
                'chain_mid should be installed as transitive dep');
            testCase.verifyTrue(exist(endDir, 'dir') > 0, ...
                'chain_end should be installed as transitive dep');
        end

        function testLoad_ChainedDeps_AllLoaded(testCase)
            mip.install('mip-org/test-channel1/chain_top');
            mip.load('mip-org/test-channel1/chain_top');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/chain_top'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/chain_mid'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/chain_end'));
        end

        function testLoad_ChainedDeps_OnlyTopDirectlyLoaded(testCase)
            mip.install('mip-org/test-channel1/chain_top');
            mip.load('mip-org/test-channel1/chain_top');

            testCase.verifyTrue(mip.state.is_directly_loaded('mip-org/test-channel1/chain_top'));
            testCase.verifyFalse(mip.state.is_directly_loaded('mip-org/test-channel1/chain_mid'));
            testCase.verifyFalse(mip.state.is_directly_loaded('mip-org/test-channel1/chain_end'));
        end

        function testUnload_ChainedDeps_AllPruned(testCase)
            mip.install('mip-org/test-channel1/chain_top');
            mip.load('mip-org/test-channel1/chain_top');
            mip.unload('mip-org/test-channel1/chain_top');

            testCase.verifyFalse(mip.state.is_loaded('mip-org/test-channel1/chain_top'));
            testCase.verifyFalse(mip.state.is_loaded('mip-org/test-channel1/chain_mid'));
            testCase.verifyFalse(mip.state.is_loaded('mip-org/test-channel1/chain_end'));
        end

        function testLoad_ChainedDeps_FunctionsAccessible(testCase)
            mip.install('mip-org/test-channel1/chain_top');
            mip.load('mip-org/test-channel1/chain_top');

            testCase.verifyTrue(contains(chain_top(), 'chain_top'));
            testCase.verifyTrue(contains(chain_mid(), 'chain_mid'));
            testCase.verifyTrue(contains(chain_end(), 'chain_end'));
        end

        %% === Multi-channel dependencies ===

        function testInstall_MultiChannelDeps(testCase)
            % multi_dep depends on alpha (ch1) and beta (ch2)
            mip.install('mip-org/test-channel2/multi_dep');

            multiDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'multi_dep');
            alphaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            betaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'beta');

            testCase.verifyTrue(exist(multiDir, 'dir') > 0, ...
                'multi_dep should be installed');
            testCase.verifyTrue(exist(alphaDir, 'dir') > 0, ...
                'alpha should be installed from test-channel1');
            testCase.verifyTrue(exist(betaDir, 'dir') > 0, ...
                'beta should be installed from test-channel2');
        end

        function testLoad_MultiChannelDeps_AllLoaded(testCase)
            mip.install('mip-org/test-channel2/multi_dep');
            mip.load('mip-org/test-channel2/multi_dep');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel2/multi_dep'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/alpha'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel2/beta'));
        end

        %% === Diamond dependency graph ===

        function testInstall_DiamondDeps_AllInstalled(testCase)
            % diamond_top -> diamond_left + diamond_right -> beta
            mip.install('mip-org/test-channel2/diamond_top');

            topDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'diamond_top');
            leftDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'diamond_left');
            rightDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'diamond_right');
            betaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'beta');

            testCase.verifyTrue(exist(topDir, 'dir') > 0);
            testCase.verifyTrue(exist(leftDir, 'dir') > 0);
            testCase.verifyTrue(exist(rightDir, 'dir') > 0);
            testCase.verifyTrue(exist(betaDir, 'dir') > 0, ...
                'beta should be installed as shared dependency');
        end

        function testLoad_DiamondDeps_AllLoaded(testCase)
            mip.install('mip-org/test-channel2/diamond_top');
            mip.load('mip-org/test-channel2/diamond_top');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel2/diamond_top'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel2/diamond_left'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel2/diamond_right'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel2/beta'));
        end

        function testUnload_DiamondDeps_SharedDepPruned(testCase)
            % Unloading diamond_top should prune all deps including
            % the shared beta dependency
            mip.install('mip-org/test-channel2/diamond_top');
            mip.load('mip-org/test-channel2/diamond_top');
            mip.unload('mip-org/test-channel2/diamond_top');

            testCase.verifyFalse(mip.state.is_loaded('mip-org/test-channel2/diamond_top'));
            testCase.verifyFalse(mip.state.is_loaded('mip-org/test-channel2/diamond_left'));
            testCase.verifyFalse(mip.state.is_loaded('mip-org/test-channel2/diamond_right'));
            testCase.verifyFalse(mip.state.is_loaded('mip-org/test-channel2/beta'), ...
                'Shared dep beta should be pruned when no direct loads remain');
        end

        function testLoad_DiamondAndDirect_SharedDepPreserved(testCase)
            % If beta is also directly loaded, unloading diamond_top
            % should NOT prune beta
            mip.install('mip-org/test-channel2/diamond_top');
            mip.load('mip-org/test-channel2/beta');
            mip.load('mip-org/test-channel2/diamond_top');

            mip.unload('mip-org/test-channel2/diamond_top');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel2/beta'), ...
                'Directly loaded beta should survive diamond_top unload');
        end

        %% === Uninstall with dependency pruning ===

        function testUninstall_PrunesTransitiveDeps(testCase)
            % Install chain_top (pulls in chain_mid + chain_end).
            % Uninstalling chain_top should prune both transitive deps.
            mip.install('mip-org/test-channel1/chain_top');

            midDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_mid');
            endDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_end');
            testCase.verifyTrue(exist(midDir, 'dir') > 0);
            testCase.verifyTrue(exist(endDir, 'dir') > 0);

            mip.uninstall('mip-org/test-channel1/chain_top');

            topDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_top');
            testCase.verifyFalse(exist(topDir, 'dir') > 0, ...
                'chain_top should be uninstalled');
            testCase.verifyFalse(exist(midDir, 'dir') > 0, ...
                'chain_mid should be pruned as orphan');
            testCase.verifyFalse(exist(endDir, 'dir') > 0, ...
                'chain_end should be pruned as orphan');
        end

        function testUninstall_PreservesSharedDeps(testCase)
            % Install delta (depends on alpha) and gamma (depends on alpha).
            % Uninstalling delta should NOT prune alpha (still needed by gamma).
            mip.install('mip-org/test-channel1/delta');
            mip.install('mip-org/test-channel1/gamma');

            alphaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            testCase.verifyTrue(exist(alphaDir, 'dir') > 0);

            mip.uninstall('mip-org/test-channel1/delta');

            testCase.verifyTrue(exist(alphaDir, 'dir') > 0, ...
                'alpha should remain (still needed by gamma)');
        end

        function testUninstall_PrunesAfterLastConsumerRemoved(testCase)
            % Install delta and gamma (both depend on alpha).
            % Uninstall both -- alpha should be pruned.
            mip.install('mip-org/test-channel1/delta');
            mip.install('mip-org/test-channel1/gamma');

            alphaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');

            mip.uninstall('mip-org/test-channel1/delta', ...
                          'mip-org/test-channel1/gamma');

            testCase.verifyFalse(exist(alphaDir, 'dir') > 0, ...
                'alpha should be pruned after both consumers uninstalled');
        end

        function testUninstall_DiamondDeps_PrunesAll(testCase)
            % Install diamond_top (diamond graph with shared beta dep).
            % Uninstalling diamond_top should prune everything.
            mip.install('mip-org/test-channel2/diamond_top');

            mip.uninstall('mip-org/test-channel2/diamond_top');

            leftDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'diamond_left');
            rightDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'diamond_right');
            betaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'beta');

            testCase.verifyFalse(exist(leftDir, 'dir') > 0, ...
                'diamond_left should be pruned');
            testCase.verifyFalse(exist(rightDir, 'dir') > 0, ...
                'diamond_right should be pruned');
            testCase.verifyFalse(exist(betaDir, 'dir') > 0, ...
                'beta should be pruned as orphan');
        end

        %% === Uninstall then reinstall ===

        function testUninstallReinstall_DepsReturn(testCase)
            % Install chain_top, uninstall it (prunes deps), reinstall it.
            mip.install('mip-org/test-channel1/chain_top');
            mip.uninstall('mip-org/test-channel1/chain_top');

            midDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_mid');
            testCase.verifyFalse(exist(midDir, 'dir') > 0);

            mip.install('mip-org/test-channel1/chain_top');

            testCase.verifyTrue(exist(midDir, 'dir') > 0, ...
                'chain_mid should be re-installed with chain_top');
        end

        %% === Load with dependencies + unload state ===

        function testLoad_WithDep_UnloadPreservesDirectlyInstalledDeps(testCase)
            % Install delta (depends on alpha) and also directly install alpha.
            % Load both. Unload delta. alpha should stay loaded (directly loaded).
            mip.install('mip-org/test-channel1/alpha');
            mip.install('mip-org/test-channel1/delta');

            mip.load('mip-org/test-channel1/alpha');
            mip.load('mip-org/test-channel1/delta');

            mip.unload('mip-org/test-channel1/delta');

            testCase.verifyTrue(mip.state.is_loaded('mip-org/test-channel1/alpha'), ...
                'alpha should remain loaded (it was directly loaded)');
        end

        %% === mip test with remote package ===

        function testTest_RemotePackageWithTestScript(testCase)
            mip.install('mip-org/test-channel1/with_test');
            output = evalc('mip.test(''mip-org/test-channel1/with_test'')');
            testCase.verifyTrue(contains(output, 'Running test script') || ...
                                contains(output, 'SUCCESS'), ...
                'mip test should run the test script');
        end

        %% === Multiple packages in single install ===

        function testInstall_MultipleFQNsAtOnce(testCase)
            mip.install('mip-org/test-channel1/chain_end', ...
                        'mip-org/test-channel2/beta');

            endDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'chain_end');
            betaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel2', 'beta');

            testCase.verifyTrue(exist(endDir, 'dir') > 0);
            testCase.verifyTrue(exist(betaDir, 'dir') > 0);
        end

        function testInstall_MultipleFQNsWithSharedDeps(testCase)
            % Install delta and gamma in one call -- both depend on alpha.
            % Alpha should be installed once.
            mip.install('mip-org/test-channel1/delta', ...
                        'mip-org/test-channel1/gamma');

            alphaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'alpha');
            deltaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'delta');
            gammaDir = fullfile(testCase.TestRoot, 'packages', ...
                'mip-org', 'test-channel1', 'gamma');

            testCase.verifyTrue(exist(alphaDir, 'dir') > 0, ...
                'alpha installed as shared dep');
            testCase.verifyTrue(exist(deltaDir, 'dir') > 0);
            testCase.verifyTrue(exist(gammaDir, 'dir') > 0);
        end

    end

end
