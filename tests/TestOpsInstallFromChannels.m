classdef TestOpsInstallFromChannels < matlab.unittest.TestCase
%TESTOPSINSTALLFROMCHANNELS   Tests for the shared channel-install engine.
%
%   Runs entirely offline: channel indexes are synthesized with
%   writeChannelIndex, and mhl_url entries point at locally-bundled .mhl
%   files (mip.channel.download_mhl accepts local paths).

    properties
        OrigMipRoot
        TestRoot
        SourceDir
        BundleDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_ops_engine_test'];
            testCase.SourceDir = [tempname '_mip_ops_engine_src'];
            testCase.BundleDir = [tempname '_mip_ops_engine_bundle'];
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
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            dirs = {testCase.TestRoot, testCase.SourceDir, testCase.BundleDir};
            for i = 1:length(dirs)
                if exist(dirs{i}, 'dir')
                    rmdir(dirs{i}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        function testInstall_MarksDirectlyInstalledByDefault(testCase)
            mhlPath = bundleTestMhl(testCase, 'enginepkg');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'enginepkg', 'mhl_url', mhlPath)});

            installedFqns = mip.ops.install_from_channels({'enginepkg'}, '');

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'core', 'enginepkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should be installed');
            testCase.verifyEqual(installedFqns, {'gh/mip-org/core/enginepkg'});
            testCase.verifyTrue(ismember('gh/mip-org/core/enginepkg', ...
                mip.state.get_directly_installed()), ...
                'Requested package should be marked directly installed');
        end

        function testInstall_TransitiveModeSkipsDirectMark(testCase)
            mhlPath = bundleTestMhl(testCase, 'transpkg');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'transpkg', 'mhl_url', mhlPath)});

            installedFqns = mip.ops.install_from_channels({'transpkg'}, '', false);

            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'core', 'transpkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package should be installed');
            testCase.verifyEqual(installedFqns, {'gh/mip-org/core/transpkg'});
            testCase.verifyFalse(ismember('gh/mip-org/core/transpkg', ...
                mip.state.get_directly_installed()), ...
                'Transitive installs must not be marked directly installed');
        end

        function testInstall_DependencyNotMarkedDirect(testCase)
            childMhl = bundleTestMhl(testCase, 'childpkg');
            parentSrc = createTestSourcePackage(testCase.SourceDir, 'parentpkg', ...
                'dependencies', {'childpkg'});
            parentMhl = bundleMhlFromSource(testCase, parentSrc, 'parentpkg');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'childpkg', 'mhl_url', childMhl), ...
                struct('name', 'parentpkg', 'mhl_url', parentMhl, ...
                       'dependencies', {{'childpkg'}})});

            mip.ops.install_from_channels({'parentpkg'}, '');

            childDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'core', 'childpkg');
            testCase.verifyTrue(exist(childDir, 'dir') > 0, ...
                'Dependency should be installed alongside the parent');
            direct = mip.state.get_directly_installed();
            testCase.verifyTrue(ismember('gh/mip-org/core/parentpkg', direct));
            testCase.verifyFalse(ismember('gh/mip-org/core/childpkg', direct), ...
                'Dependency must not be marked directly installed');
        end

        function testInstall_AlreadyInstalledPromotesToDirect(testCase)
            % Re-requesting an installed package downloads nothing but
            % promotes it to directly installed.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'oldpkg');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {'oldpkg'});

            installedFqns = mip.ops.install_from_channels({'oldpkg'}, '');

            testCase.verifyEmpty(installedFqns, ...
                'Nothing new should be installed');
            testCase.verifyTrue(ismember('gh/mip-org/core/oldpkg', ...
                mip.state.get_directly_installed()), ...
                'Already-installed package should be promoted to direct');
        end

        function testInstall_RejectsNonGhFqn(testCase)
            testCase.verifyError( ...
                @() mip.ops.install_from_channels({'local/foo'}, ''), ...
                'mip:install:invalidPackageSpec');
        end

        function testInstall_NotFoundInPriorityChannels(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            testCase.verifyError( ...
                @() mip.ops.install_from_channels({'nosuchpkg'}, ''), ...
                'mip:packageNotFound');
        end

    end

    methods (Access = private)
        function mhlPath = bundleTestMhl(testCase, pkgName)
            srcDir = createTestSourcePackage(testCase.SourceDir, pkgName);
            mhlPath = bundleMhlFromSource(testCase, srcDir, pkgName);
        end

        function mhlPath = bundleMhlFromSource(testCase, srcDir, pkgName)
            mip.bundle(srcDir, '--output', testCase.BundleDir, '--arch', 'any');
            mhlFiles = dir(fullfile(testCase.BundleDir, [pkgName '-*.mhl']));
            testCase.assertNotEmpty(mhlFiles, '.mhl bundle was not produced');
            mhlPath = fullfile(testCase.BundleDir, mhlFiles(1).name);
        end
    end
end
