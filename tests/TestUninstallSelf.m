classdef TestUninstallSelf < matlab.unittest.TestCase
%TESTUNINSTALLSELF   Tests for mip self-uninstall (uninstallSelf).

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_uninstall_self_test'];
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

        function testMipSelfUninstallDetected(testCase)
            % mip-org/core/mip FQN is correctly identified as the
            % self-uninstall trigger
            r = mip.parse.parse_package_arg('mip-org/core/mip');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.name, 'mip');

            resolvedPackages = {'mip-org/core/mip', 'mip-org/core/otherpkg'};
            testCase.verifyTrue(ismember('mip-org/core/mip', resolvedPackages));
        end

        function testSelfUninstallDetectedViaBareNameResolution(testCase)
            % 'mip uninstall mip' should trigger self-uninstall when
            % mip-org/core/mip is the only installed package named 'mip'
            mipPkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            mipSourceDir = fullfile(mipPkgDir, 'mip');
            mkdir(mipSourceDir);
            addpath(mipSourceDir);
            testCase.addTeardown(@() rmpath_safe(mipSourceDir));
            setenv('MIP_CONFIRM', 'yes');

            mip.uninstall('mip');

            testCase.verifyFalse(exist(testCase.TestRoot, 'dir') > 0, ...
                'Root directory should be deleted via bare name self-uninstall');
        end

        function testOtherChannelMipDoesNotTriggerSelfUninstall(testCase)
            % A 'mip' package on another channel should go through normal
            % uninstall, not self-uninstall. MIP_CONFIRM=yes ensures that
            % if self-uninstall is accidentally triggered, the root dir
            % gets deleted and the assertion below catches it.
            pkgDir = createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'mip');
            mip.state.add_directly_installed('mylab/custom/mip');
            setenv('MIP_CONFIRM', 'yes');

            mip.uninstall('mylab/custom/mip');

            testCase.verifyFalse(exist(pkgDir, 'dir') > 0, ...
                'Package should be uninstalled');
            testCase.verifyTrue(exist(testCase.TestRoot, 'dir') > 0, ...
                'Root directory should still exist');
        end

        function testSelfUninstallDeletesRootDir(testCase)
            mipPkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            mipSourceDir = fullfile(mipPkgDir, 'mip');
            mkdir(mipSourceDir);
            addpath(mipSourceDir);
            testCase.addTeardown(@() rmpath_safe(mipSourceDir));
            setenv('MIP_CONFIRM', 'yes');

            mip.uninstall('mip-org/core/mip');

            testCase.verifyFalse(exist(testCase.TestRoot, 'dir') > 0, ...
                'Root directory should be deleted');
        end

        function testSelfUninstallRemovesFromPath(testCase)
            mipPkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            mipSourceDir = fullfile(mipPkgDir, 'mip');
            mkdir(mipSourceDir);
            addpath(mipSourceDir);
            testCase.addTeardown(@() rmpath_safe(mipSourceDir));
            setenv('MIP_CONFIRM', 'yes');

            mip.uninstall('mip-org/core/mip');

            pathDirs = strsplit(path, pathsep);
            testCase.verifyFalse(ismember(mipSourceDir, pathDirs), ...
                'mip source dir should be off the path');
        end

        function testSelfUninstallResetsState(testCase)
            mipPkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            mipSourceDir = fullfile(mipPkgDir, 'mip');
            mkdir(mipSourceDir);
            addpath(mipSourceDir);
            testCase.addTeardown(@() rmpath_safe(mipSourceDir));
            setenv('MIP_CONFIRM', 'yes');

            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'somepkg');
            mip.load('mip-org/core/somepkg');

            mip.uninstall('mip-org/core/mip');

            testCase.verifyFalse(mip.state.is_loaded('mip-org/core/somepkg'), ...
                'Loaded packages should be cleared after self-uninstall');
        end

        function testSelfUninstallWithOtherPackages(testCase)
            % When mip-org/core/mip is uninstalled alongside other packages,
            % the root dir deletion removes everything
            mipPkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            mipSourceDir = fullfile(mipPkgDir, 'mip');
            mkdir(mipSourceDir);
            addpath(mipSourceDir);
            testCase.addTeardown(@() rmpath_safe(mipSourceDir));
            setenv('MIP_CONFIRM', 'yes');

            otherPkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'otherpkg');

            mip.uninstall('mip-org/core/mip', 'mip-org/core/otherpkg');

            testCase.verifyFalse(exist(testCase.TestRoot, 'dir') > 0, ...
                'Root directory should be deleted');
            testCase.verifyFalse(exist(otherPkgDir, 'dir') > 0, ...
                'Other package should be gone with root dir');
        end

        function testSelfUninstallAbortContinuesWithOtherPackages(testCase)
            % When user declines self-uninstall, other packages should
            % still be uninstalled
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'otherpkg');
            mip.state.add_directly_installed('mip-org/core/otherpkg');
            setenv('MIP_CONFIRM', 'no');

            mip.uninstall('mip-org/core/mip', 'mip-org/core/otherpkg');

            testCase.verifyTrue(exist(testCase.TestRoot, 'dir') > 0, ...
                'Root directory should still exist after abort');
            testCase.verifyFalse(exist(pkgDir, 'dir') > 0, ...
                'Other package should still be uninstalled');
        end

    end
end

function rmpath_safe(d)
    w = warning('off', 'MATLAB:rmpath:DirNotFound');
    rmpath(d);
    warning(w);
end
