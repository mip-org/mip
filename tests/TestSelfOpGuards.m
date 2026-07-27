classdef TestSelfOpGuards < matlab.unittest.TestCase
%TESTSELFOPGUARDS   Self-operation preconditions on the main mip
%   (specification §1.7.1, docs/mip_self_scenarios.md).
%
%   mip.self.op_state classifies the session (ok / standalone / env /
%   mip-loaded), and the self operations — mip update mip, mip uninstall
%   mip, mip install mip@<version> — proceed only in the 'ok' state:
%   standalone sessions get a message refusal, an active environment gets
%   mip:self:envActive, and a loaded other mip gets
%   mip:self:otherMipLoaded. A loaded package providing the running mip
%   can never be updated or uninstalled (mip:update:runningMip /
%   mip:uninstall:runningMip).

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_selfop_root'];
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

        % ---- op_state classification ----

        function testOpStateStandaloneByDefault(testCase)
            % No mip installed in the root that runs the session: standalone.
            s = mip.self.op_state();
            testCase.verifyEqual(s.state, 'standalone');
        end

        function testOpStateOkWithRunningMip(testCase)
            testCase.makeOwnRoot();
            s = mip.self.op_state();
            testCase.verifyEqual(s.state, 'ok');
            testCase.verifyEmpty(s.blockers);
        end

        function testOpStateEnvActive(testCase)
            testCase.makeOwnRoot();
            testCase.activateScratchEnv();
            s = mip.self.op_state();
            testCase.verifyEqual(s.state, 'env');
        end

        function testOpStateOtherMipLoaded(testCase)
            testCase.makeOwnRoot();
            testCase.loadPreviewMip('labs');
            s = mip.self.op_state();
            testCase.verifyEqual(s.state, 'mip-loaded');
            testCase.verifyTrue(ismember('gh/mip-org/labs/mip', s.blockers));
        end

        function testOpStateStandalonePrecedesEnv(testCase)
            % Scenario 23: a standalone session stays standalone inside an
            % environment — deactivating would not make the main mip
            % manageable.
            testCase.activateScratchEnv();
            s = mip.self.op_state();
            testCase.verifyEqual(s.state, 'standalone');
        end

        % ---- another mip loaded (Scenarios 11, 12) ----

        function testUpdateMipRefusedWhileOtherMipLoaded(testCase)
            testCase.makeOwnRoot();
            testCase.loadPreviewMip('labs');
            testCase.verifyError(@() evalc('mip.update(''mip'')'), ...
                                 'mip:self:otherMipLoaded');
        end

        function testUninstallMipRefusedWhileOtherMipLoaded(testCase)
            testCase.makeOwnRoot();
            testCase.loadPreviewMip('labs');
            setenv('MIP_CONFIRM', 'yes');
            testCase.verifyError(@() evalc('mip.uninstall(''mip-org/core/mip'')'), ...
                                 'mip:self:otherMipLoaded');
            testCase.verifyTrue(mip.paths.is_valid_root(testCase.TestRoot), ...
                'The refusal must leave the root untouched');
        end

        function testInstallMipVersionRefusedWhileOtherMipLoaded(testCase)
            % Scenario 11 note: mip install mip@<version> is the same
            % mechanism as the self-update, so the same rule applies. The
            % guard fires before any index fetch, so no network is needed.
            testCase.makeOwnRoot();
            testCase.loadPreviewMip('labs');
            testCase.verifyError(@() evalc('mip.install(''mip-org/core/mip@0.0.1'')'), ...
                                 'mip:self:otherMipLoaded');
        end

        % ---- running mip cannot be updated/uninstalled (Scenario 13) ----

        function testUpdateRunningPreviewRefused(testCase)
            testCase.loadPreviewMip('labs');
            testCase.verifyError(@() evalc('mip.update(''mip-org/labs/mip'')'), ...
                                 'mip:update:runningMip');
        end

        function testUninstallRunningPreviewRefused(testCase)
            testCase.loadPreviewMip('labs');
            testCase.verifyError(@() evalc('mip.uninstall(''mip-org/labs/mip'')'), ...
                                 'mip:uninstall:runningMip');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'));
        end

        function testUnloadedPreviewUpdatesNormally(testCase)
            % Once unloaded, the preview is an ordinary package again: the
            % running-mip guard no longer fires. A cached fake channel
            % index (invalid download URL) lets the update proceed past
            % the guard offline and fail in the download step instead.
            testCase.loadPreviewMip('labs');
            evalc('mip.unload(''mip-org/labs/mip'')');
            writeChannelIndex(testCase.TestRoot, 'mip-org/labs', ...
                {struct('name', 'mip', 'version', '2.0.0')});
            try
                evalc('mip.update(''mip-org/labs/mip'')');
                err = [];
            catch e
                err = e;
            end
            testCase.verifyNotEmpty(err);
            testCase.verifyNotEqual(err.identifier, 'mip:update:runningMip');
        end

        % ---- standalone session (Scenarios 14, 15, 16) ----

        function testUpdateMipStandaloneMessage(testCase)
            output = evalc('mip.update(''mip'')');
            testCase.verifySubstring(output, 'standalone');
            testCase.verifyTrue(mip.paths.is_valid_root(testCase.TestRoot));
        end

        function testUninstallMipStandaloneMessage(testCase)
            setenv('MIP_CONFIRM', 'yes');  % must not matter: no teardown runs
            output = evalc('mip.uninstall(''mip'')');
            testCase.verifySubstring(output, 'standalone');
            testCase.verifySubstring(output, 'no teardown');
            testCase.verifyTrue(mip.paths.is_valid_root(testCase.TestRoot), ...
                'The root is never deleted in standalone mode');
        end

        function testInstallMipStandaloneRefused(testCase)
            % The guard fires before any index fetch, so no network is
            % needed, and no core-identity copy may be created.
            output = evalc('mip.install(''mip'')');
            testCase.verifySubstring(output, 'Refusing to install');
            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, ...
                'packages', 'gh', 'mip-org', 'core', 'mip')));
            testCase.verifyEmpty(strfind(output, 'All packages already installed'));
        end

        function testStandaloneInertCopyUninstallsOrdinarily(testCase)
            % A leftover inert copy of the identity in a root the running
            % mip does not manage stays an ordinary package: uninstall
            % removes it, no confirmation, and the root survives.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            mip.state.add_directly_installed('gh/mip-org/core/mip');
            setenv('MIP_CONFIRM', 'no');  % would abort a self-uninstall

            evalc('mip.uninstall(''mip'')');

            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, ...
                'packages', 'gh', 'mip-org', 'core', 'mip')));
            testCase.verifyTrue(mip.paths.is_valid_root(testCase.TestRoot));
        end

        % ---- active environment (Scenario 22) ----

        function testSelfOpsRefusedWhileEnvActive(testCase)
            testCase.makeOwnRoot();
            testCase.activateScratchEnv();
            testCase.verifyError(@() evalc('mip.update(''mip'')'), 'mip:self:envActive');
            testCase.verifyError(@() evalc('mip.uninstall(''mip'')'), 'mip:self:envActive');
            testCase.verifyError(@() evalc('mip.install(''mip@1.2.3'')'), 'mip:self:envActive');
        end

        % ---- bulk update skips instead of erroring ----

        function testUpdateAllSkipsGuardedPackages(testCase)
            testCase.makeOwnRoot();
            testCase.loadPreviewMip('labs');
            output = evalc('mip.update(''--all'')');
            testCase.verifySubstring(output, 'Skipping');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'The running preview must be skipped, not touched');
        end

    end

    methods
        function makeOwnRoot(testCase)
            % Make the test root look like the main root of the running
            % mip: seed gh/mip-org/core/mip and plant a stub mip.m on the
            % path (cleaned up by cleanupTestPaths in teardown).
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            plantStubMip(pkgDir);
        end

        function activateScratchEnv(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));
        end

        function loadPreviewMip(testCase, channel)
            % Seed and load gh/mip-org/<channel>/mip whose source ships a
            % stub mip.m: from the session's point of view this package now
            % provides the running mip.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', channel, 'mip');
            fid = fopen(fullfile(pkgDir, 'mip', 'mip.m'), 'w');
            fprintf(fid, 'function varargout = mip(varargin) %%#ok<STOUT,VANUS>\nend\n');
            fclose(fid);
            evalc(sprintf('mip.load(''mip-org/%s/mip'')', channel));
        end
    end
end
