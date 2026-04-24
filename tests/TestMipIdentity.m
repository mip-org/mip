classdef TestMipIdentity < matlab.unittest.TestCase
%TESTMIPIDENTITY   Tests that mip-org/core/mip special handling only
%   applies to the specific FQN and not to other packages named 'mip'.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
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

        function testCannotUnloadMipOrgCoreMip(testCase)
            testCase.verifyError(@() mip.unload('mip-org/core/mip'), ...
                'mip:cannotUnloadMip');
        end

        function testCanUnloadMipOnOtherChannel(testCase)
            % A package named 'mip' on a different channel should be unloadable
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'mip');
            mip.load('mylab/custom/mip');
            testCase.verifyTrue(mip.state.is_loaded('mylab/custom/mip'));

            mip.unload('mylab/custom/mip');
            testCase.verifyFalse(mip.state.is_loaded('mylab/custom/mip'));
        end

        function testCanUnloadMipLocalInstall(testCase)
            % A local/editable 'mip' package should be unloadable
            createTestPackage(testCase.TestRoot, '', '', 'mip', 'type', 'local');
            mip.load('local/mip');
            testCase.verifyTrue(mip.state.is_loaded('local/mip'));

            mip.unload('local/mip');
            testCase.verifyFalse(mip.state.is_loaded('local/mip'));
        end

        function testMipOrgCoreMipAlwaysLoadedMessage(testCase)
            % Loading mip-org/core/mip should not error (it prints a message)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            mip.load('mip-org/core/mip');
        end

        function testUnloadAllForce_NeverUnloadsMipOrgCoreMip(testCase)
            mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/mip');
            mip.state.key_value_append('MIP_STICKY_PACKAGES', 'gh/mip-org/core/mip');

            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'mip');
            mip.load('mylab/custom/mip');

            mip.unload('--all', '--force');

            % gh/mip-org/core/mip should still be loaded
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/mip'));
            % mylab/custom/mip should be unloaded
            testCase.verifyFalse(mip.state.is_loaded('mylab/custom/mip'));
        end

        function testMipEntryPoint_SetsFqn(testCase)
            % After calling mip(), MIP_LOADED_PACKAGES should contain
            % 'gh/mip-org/core/mip' (canonical FQN, not path-derived)
            clearMipState();
            mip('version');
            loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
            testCase.verifyTrue(ismember('gh/mip-org/core/mip', loaded), ...
                'gh/mip-org/core/mip should be in MIP_LOADED_PACKAGES after calling mip()');
        end

        function testMipEntryPoint_SetsSticky(testCase)
            clearMipState();
            mip('version');
            sticky = mip.state.key_value_get('MIP_STICKY_PACKAGES');
            testCase.verifyTrue(ismember('gh/mip-org/core/mip', sticky), ...
                'gh/mip-org/core/mip should be in MIP_STICKY_PACKAGES after calling mip()');
        end

        function testMipEntryPoint_NoGarbageFqn(testCase)
            % Verify that no path-derived garbage FQN is added
            clearMipState();
            mip('version');
            loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
            for i = 1:length(loaded)
                fqn = loaded{i};
                r = mip.parse.parse_package_arg(fqn);
                testCase.verifyTrue(r.is_fqn, ...
                    sprintf('Loaded package "%s" is not a valid FQN', fqn));
            end
        end

        function testLoadCustomMip_DoesNotGetMipSpecialTreatment(testCase)
            % Loading a 'mip' package from another org should go through
            % normal loading flow (not short-circuit)
            createTestPackage(testCase.TestRoot, 'other-org', 'test', 'mip');
            mip.load('other-org/test/mip');
            testCase.verifyTrue(mip.state.is_loaded('other-org/test/mip'));
            testCase.verifyTrue(mip.state.is_directly_loaded('other-org/test/mip'));
        end

    end
end
