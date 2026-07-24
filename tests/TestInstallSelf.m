classdef TestInstallSelf < matlab.unittest.TestCase
%TESTINSTALLSELF   End-to-end test for switching mip's own version via
%   `mip install mip@<version>` (the self-install hot-swap path).
%
%   mip cannot switch its own version through the normal unload/replace
%   path (it is the running code, and mip.unload rejects the self identity),
%   so install.m routes a version switch of gh/mip-org/core/mip through
%   mip.self.hot_swap instead. This test exercises that route by seeding a
%   fake numeric mip-org/core/mip into an isolated MIP_ROOT and switching it
%   to the "main" branch from the real mip-org/core channel.
%
%   Like TestUpdateSelf, this cannot be redirected at a fake channel because
%   the self identity is hard-coded to gh/mip-org/core/mip. The seeded
%   version is a fake 0.0.0 (never published) and the target is the "main"
%   branch, which is durable — a numeric release tag could be removed from
%   the channel later, but the branch persists.
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
            testCase.TestRoot = [tempname '_mip_install_self_test'];
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

        function testInstallSelf_SwitchNumericToBranch(testCase)
            % Seed a fake numeric mip so resolve_to_installed finds a target
            % but the version never matches anything real in the channel.
            pkgDir = createTestPackage(testCase.TestRoot, ...
                'mip-org', 'core', 'mip', 'version', '0.0.0');
            % The hot swap only triggers when the seeded package looks
            % like the running mip (MEP 8 self-flow guard).
            plantStubMip(pkgDir);
            info1 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info1.version, '0.0.0');

            % Because the installed version (0.0.0) differs from the
            % requested one (main), install.m must hot-swap mip in place
            % rather than routing through the unload/replace path (which
            % would hit mip:cannotUnloadMip). This hits the real
            % mip-org/core channel, downloads the mip mhl, rmpaths+rmdirs
            % the fake, and movefiles the real payload into the test root.
            mip.install('mip-org/core/mip@main');

            % Drop any MATLAB path entries the downloaded mip just added so
            % the verify calls below run against the repo's mip.* functions,
            % not the test-root payload.
            cleanupTestPaths(testCase.TestRoot);

            % The swap succeeded: directory still present, version is now the
            % requested branch, and the payload looks like a real mip install.
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'mip-org/core/mip should still exist after self-install');
            info2 = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info2.version, 'main', ...
                'version should be replaced with the requested "main" branch');
            testCase.verifyEqual(info2.name, 'mip', ...
                'mip.json name should be "mip"');
            testCase.verifyTrue(isfield(info2, 'paths'), ...
                'downloaded mip payload should expose mip.json "paths"');
        end

    end
end
