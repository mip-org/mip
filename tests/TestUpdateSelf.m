classdef TestUpdateSelf < matlab.unittest.TestCase
%TESTUPDATESELF   End-to-end test for `mip update mip` (self-update).
%
%   Exercises the updateSelf code path in mip.update by installing a
%   fake mip-org/core/mip into an isolated MIP_ROOT, then running
%   mip.update --force to trigger a full download-and-swap against the
%   real mip-org/core channel. Exists to catch regressions in the
%   self-update tail (see mip-org/mip#140) — that code path is otherwise
%   uncovered because updateSelf is hard-coded to mip-org/core/mip and
%   cannot be redirected at a fake channel.
%
%   Requires network access to GitHub Pages.
%   Skipped in run_tests() when MIP_SKIP_REMOTE is set.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_update_self_test'];
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

        function testUpdateSelf_ForceReplacesFakeWithReal(testCase)
            % Seed a fake mip-org/core/mip in the test root so that
            % resolve_to_installed finds it and updateSelf has a target.
            pkgDir = createTestPackage(testCase.TestRoot, ...
                'mip-org', 'core', 'mip', 'version', '0.0.0-fake');
            info1 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info1.version, '0.0.0-fake');

            % Force self-update. This hits the real mip-org/core channel,
            % downloads the mip mhl, unloads+rmdirs the fake, and
            % movefiles the real payload into the test root. Every line
            % of updateSelf runs in this call — including the post-swap
            % fprintfs that broke in mip-org/mip#140. Any regression
            % there surfaces here as a test error.
            mip.update('--force', 'mip-org/core/mip');

            % Remove any MATLAB path entries the downloaded mip's
            % load_package.m just added, so the verify calls below run
            % against the repo's mip.* functions, not the test-root
            % payload (they should be equivalent, but keeping the path
            % clean avoids surprises if they ever diverge).
            cleanupTestPaths(testCase.TestRoot);

            % Verify the swap succeeded: directory still present, version
            % is no longer the fake marker, and the payload looks like a
            % real mip install.
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'mip-org/core/mip should still exist after self-update');
            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyNotEqual(info2.version, '0.0.0-fake', ...
                'version should be replaced with real mip version from channel');
            testCase.verifyEqual(info2.name, 'mip', ...
                'mip.json name should be "mip"');
            testCase.verifyTrue(exist(fullfile(pkgDir, 'load_package.m'), 'file') > 0, ...
                'downloaded mip payload should contain load_package.m');
        end

    end
end
