classdef TestInstallMhl < matlab.unittest.TestCase
%TESTINSTALLMHL   Tests for `mip install <path-to.mhl>` source-type routing.
% A .mhl installed without `--channel` must land under the `mhl/` source
% type, not under `gh/mip-org/core/`. Passing `--channel <org>/<chan>`
% opts in to gh-channel placement.

    properties
        OrigMipRoot
        TestRoot
        SourceDir
        BundleDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_install_mhl_test'];
            testCase.SourceDir = [tempname '_mip_install_mhl_src'];
            testCase.BundleDir = [tempname '_mip_install_mhl_bundle'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.SourceDir);
            mkdir(testCase.BundleDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.SourceDir);
            cleanupTestPaths(testCase.BundleDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            for d = {testCase.TestRoot, testCase.SourceDir, testCase.BundleDir}
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        function testMhlInstall_NoChannel_LandsUnderMhlSourceType(testCase)
            % A .mhl installed without `--channel` must NOT silently land
            % under gh/mip-org/core/. It must land under packages/mhl/
            % so a third-party archive cannot masquerade as a core member.
            mhlPath = bundleTestPackage(testCase, 'mhl_pkg');

            mip.install(mhlPath);

            mhlDir = fullfile(testCase.TestRoot, 'packages', 'mhl', 'mhl_pkg');
            coreDir = fullfile(testCase.TestRoot, 'packages', ...
                               'gh', 'mip-org', 'core', 'mhl_pkg');
            testCase.verifyTrue(exist(mhlDir, 'dir') > 0, ...
                '.mhl install with no --channel should land under packages/mhl/');
            testCase.verifyFalse(exist(coreDir, 'dir') > 0, ...
                '.mhl install with no --channel must NOT land under mip-org/core/');
        end

        function testMhlInstall_NoChannel_RecordedAsMhlFqn(testCase)
            % The directly-installed FQN must use the mhl/ source type, so
            % `mip list` and friends do not display the package as a core
            % channel package.
            mhlPath = bundleTestPackage(testCase, 'mhl_pkg2');

            mip.install(mhlPath);

            installed = mip.state.get_directly_installed();
            testCase.verifyTrue(ismember('mhl/mhl_pkg2', installed), ...
                'directly_installed should record FQN as mhl/<name>');
            testCase.verifyFalse(ismember('gh/mip-org/core/mhl_pkg2', installed), ...
                'must not record under gh/mip-org/core');
        end

        function testMhlInstall_WithChannel_StillUsesGhChannel(testCase)
            % When --channel is given, the explicit opt-in is preserved:
            % the package is placed under gh/<org>/<channel>/.
            mhlPath = bundleTestPackage(testCase, 'mhl_pkg3');

            mip.install('--channel', 'mylab/custom', mhlPath);

            ghDir = fullfile(testCase.TestRoot, 'packages', ...
                             'gh', 'mylab', 'custom', 'mhl_pkg3');
            mhlDir = fullfile(testCase.TestRoot, 'packages', 'mhl', 'mhl_pkg3');
            testCase.verifyTrue(exist(ghDir, 'dir') > 0, ...
                '--channel mylab/custom should place under gh/mylab/custom/');
            testCase.verifyFalse(exist(mhlDir, 'dir') > 0, ...
                'must not also land under mhl/ when --channel was given');
        end

    end
end


function mhlPath = bundleTestPackage(testCase, pkgName)
%BUNDLETESTPACKAGE   Build a fresh .mhl from a generated source package.
    srcDir = createTestSourcePackage(testCase.SourceDir, pkgName);
    mip.bundle(srcDir, '--output', testCase.BundleDir, '--arch', 'any');
    mhlFiles = dir(fullfile(testCase.BundleDir, [pkgName '-*.mhl']));
    testCase.assertNotEmpty(mhlFiles, '.mhl bundle was not produced');
    mhlPath = fullfile(testCase.BundleDir, mhlFiles(1).name);
end
