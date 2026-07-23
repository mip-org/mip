classdef TestRunningMipGuard < matlab.unittest.TestCase
%TESTRUNNINGMIPGUARD   Bulk unloads never unload the package providing
%   the running mip (MEP 8): a preview build of mip loaded over the
%   released one (simulated here by a gh/mip-org/labs/mip package whose
%   source dir ships a stub mip.m) survives unload --all [--force], the
%   activation swap, and pruning. Explicit unload still works.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_runningmip_root'];
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

        function testDetectionFindsLoadedPreview(testCase)
            testCase.verifyEmpty(mip.self.running_mip_fqn(), ...
                'No loaded package provides mip yet');
            srcDir = testCase.loadPreviewMip();
            testCase.verifyEqual(mip.self.running_mip_fqn(), 'gh/mip-org/labs/mip');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));
        end

        function testUnloadAllForceSparesPreview(testCase)
            srcDir = testCase.loadPreviewMip();
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'other');
            evalc('mip.load(''other'', ''--sticky'')');

            evalc('mip.unload(''--all'', ''--force'')');

            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/other'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'The running preview mip must survive unload --all --force');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));
            testCase.verifyTrue(mip.state.is_directly_loaded('gh/mip-org/labs/mip'), ...
                'The spared package keeps its direct flag');
        end

        function testUnloadAllSparesNonStickyPreview(testCase)
            % The preview is loaded without --sticky; plain unload --all
            % must spare it anyway.
            testCase.loadPreviewMip();
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'other');
            evalc('mip.load(''other'')');

            evalc('mip.unload(''--all'')');

            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/other'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'));
        end

        function testExplicitUnloadStillWorks(testCase)
            srcDir = testCase.loadPreviewMip();
            evalc('mip.unload(''mip-org/labs/mip'')');
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'Explicit unload is the preview exit ramp and must work');
            testCase.verifyFalse(ismember(srcDir, strsplit(path, pathsep)));
        end

        function testPruneSparesTransitivelyLoadedPreview(testCase)
            % Even loaded as a transitive dep (no direct flag), the
            % preview is not pruned as an orphan.
            testCase.loadPreviewMip('--transitive');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'other');
            evalc('mip.load(''other'')');

            evalc('mip.unload(''other'')');

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'Pruning must never drop the running mip');
        end

        function testPreviewSurvivesActivationRoundTrip(testCase)
            srcDir = testCase.loadPreviewMip();
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'other');
            otherSrc = fullfile(pkgDir, 'other');
            evalc('mip.load(''other'', ''--sticky'')');

            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'The preview must survive the activation swap');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/other'), ...
                'Everything else still swaps out');
            testCase.verifyFalse(ismember(otherSrc, strsplit(path, pathsep)));

            s = mip.state.get_env_state();
            testCase.verifyEqual(s.running_mip, 'gh/mip-org/labs/mip');

            % A bulk unload inside the env also spares it (detection uses
            % the activation-time value; the preview is not installed in
            % the env).
            evalc('mip.unload(''--all'', ''--force'')');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'));

            evalc('mip.env(''deactivate'')');

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'The preview must survive deactivation');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/other'), ...
                'The saved package set is restored');
            testCase.verifyTrue(mip.state.is_sticky('gh/mip-org/core/other'));
        end

        function testPreviewSurvivesDeletedEnvDeactivate(testCase)
            srcDir = testCase.loadPreviewMip();
            evalc('mip.env(''create'', ''doomed'')');
            evalc('mip.env(''activate'', ''doomed'')');
            envRoot = mip.state.get_env_state().root;

            rmdir(envRoot, 's');
            evalc('mip.env(''deactivate'')');

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'The preview must survive deactivation of a deleted env');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));
        end

    end

    methods
        function srcDir = loadPreviewMip(testCase, varargin)
            % Seed gh/mip-org/labs/mip whose source dir ships a stub
            % mip.m, and load it — from the session's point of view this
            % package now provides the running mip.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'labs', 'mip');
            srcDir = fullfile(pkgDir, 'mip');
            fid = fopen(fullfile(srcDir, 'mip.m'), 'w');
            fprintf(fid, 'function varargout = mip(varargin) %%#ok<STOUT,VANUS>\nend\n');
            fclose(fid);
            evalc('mip.load(''mip-org/labs/mip'', varargin{:})');
        end
    end
end
