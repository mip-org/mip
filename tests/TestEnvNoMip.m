classdef TestEnvNoMip < matlab.unittest.TestCase
%TESTENVNOMIP   No mip package — core or otherwise — may be installed
%   into or loaded from an environment (specification §14.7, scenarios
%   doc Scenario 19). The refusal is mip:env:noMip and fires for every
%   install type and for loads, without depending on the package being
%   installed. mip load mip stays the "always loaded" no-op (Scenario 1).

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_env_nomip_root'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
            % Make the test root the main root of the running mip, then
            % activate an environment in it.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            plantStubMip(pkgDir);
            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            evalc('mip.env(''deactivate'')');
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testInstallOtherMipRefused(testCase)
            % Channel install of a non-core mip: refused before any index
            % fetch, so no network is needed.
            testCase.verifyError(@() evalc('mip.install(''mylab/custom/mip'')'), ...
                                 'mip:env:noMip');
        end

        function testInstallBareMipRefused(testCase)
            % Versionless core-identity install in an env: Scenario 19's
            % refusal (the @version form gets mip:self:envActive instead,
            % covered in TestSelfOpGuards).
            testCase.verifyError(@() evalc('mip.install(''mip'')'), ...
                                 'mip:env:noMip');
        end

        function testInstallLocalMipRefused(testCase)
            srcParent = [tempname '_mip_env_nomip_src'];
            mkdir(srcParent);
            testCase.addTeardown(@() rmdir(srcParent, 's'));
            srcDir = createTestSourcePackage(srcParent, 'mip');
            testCase.verifyError(@() evalc(sprintf('mip.install(''%s'')', srcDir)), ...
                                 'mip:env:noMip');
        end

        function testLoadOtherMipRefused(testCase)
            % Refused before resolution: the package need not be installed.
            testCase.verifyError(@() evalc('mip.load(''mylab/custom/mip'')'), ...
                                 'mip:env:noMip');
        end

        function testLoadBareMipIsAlwaysLoadedNoOp(testCase)
            output = evalc('mip.load(''mip'')');
            testCase.verifySubstring(output, 'always loaded');
        end

        function testLoadIdentityFqnIsAlwaysLoadedNoOp(testCase)
            output = evalc('mip.load(''mip-org/core/mip'')');
            testCase.verifySubstring(output, 'always loaded');
        end

        function testOrdinaryInstallStillWorksInEnv(testCase)
            % The guard is specific to mip-named packages: an ordinary
            % local install into the environment proceeds.
            srcParent = [tempname '_mip_env_nomip_src2'];
            mkdir(srcParent);
            testCase.addTeardown(@() rmdir(srcParent, 's'));
            srcDir = createTestSourcePackage(srcParent, 'plainpkg');
            evalc(sprintf('mip.install(''%s'')', srcDir));
            envRoot = mip.state.get_env_state().root;
            testCase.verifyTrue(isfolder(fullfile(envRoot, 'packages', 'local', 'plainpkg')));
        end

    end
end
