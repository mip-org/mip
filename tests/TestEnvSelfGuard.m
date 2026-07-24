classdef TestEnvSelfGuard < matlab.unittest.TestCase
%TESTENVSELFGUARD   MEP 8: the self flows trigger only when the active
%   root is the root mip actually runs from; elsewhere the identity
%   gh/mip-org/core/mip is an ordinary, inert package.

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_env_selfguard_root'];
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
            setenv('MIP_CONFIRM', testCase.OrigMipConfirm);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testIsOwnRootFalseWithoutRunningMip(testCase)
            % The seeded copy of mip is not the running mip, so the
            % active (test) root is not mip's own root.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            testCase.verifyFalse(mip.self.is_own_root());
        end

        function testIsOwnRootFalseWithNoMipInstalled(testCase)
            testCase.verifyFalse(mip.self.is_own_root());
        end

        function testIsOwnRootTrueWhenRunningFromActiveRoot(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            plantStubMip(pkgDir);
            testCase.verifyTrue(mip.self.is_own_root());
        end

        function testUninstallMipInsideEnvIsOrdinary(testCase)
            % Inside an activated env, `mip uninstall mip` removes the
            % env's inert copy; the env root survives and no confirmation
            % runs (MIP_CONFIRM=no would abort a self-uninstall).
            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));
            envRoot = mip.state.get_env_state().root;

            mipCopyDir = createTestPackage(envRoot, 'mip-org', 'core', 'mip');
            mip.state.add_directly_installed('gh/mip-org/core/mip');
            setenv('MIP_CONFIRM', 'no');

            evalc('mip.uninstall(''mip'')');

            testCase.verifyFalse(exist(mipCopyDir, 'dir') > 0, ...
                'The env copy of mip should be uninstalled like any package');
            testCase.verifyTrue(mip.paths.is_valid_root(envRoot), ...
                'The env root must survive');
        end

        function testUninstallMipInsideEnvNotInstalled(testCase)
            % With no copy in the env, `mip uninstall mip` reports "not
            % installed" rather than touching anything.
            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));
            envRoot = mip.state.get_env_state().root;

            output = evalc('mip.uninstall(''mip'')');
            testCase.verifyTrue(contains(output, 'not installed'));
            testCase.verifyTrue(mip.paths.is_valid_root(envRoot));
        end

    end
end
