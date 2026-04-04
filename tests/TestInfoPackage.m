classdef TestInfoPackage < matlab.unittest.TestCase
%TESTINFOPACKAGE   Tests for the local-installation portion of mip.info.
%
%   These tests verify that mip.info displays local installation info
%   (version, path, loaded status, dependencies, editable flag) without
%   requiring network access. Remote channel queries are tested in the
%   integration tests.

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_info_test'];
            testCase.SourceDir = [tempname '_mip_src'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            if exist(testCase.SourceDir, 'dir')
                rmdir(testCase.SourceDir, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        %% --- Local install info shown ---

        function testInfoShowsInstalledVersion(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg', ...
                'version', '2.3.0');

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, '2.3.0'), ...
                'Info should display installed version');
        end

        function testInfoShowsInstallationPath(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg');

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'Path:'), ...
                'Info should display installation path');
            testCase.verifyTrue(contains(output, testCase.TestRoot), ...
                'Path should point into test root');
        end

        function testInfoShowsNotInstalledWhenRemoteExists(testCase)
            % Package not installed locally but exists in a remote channel
            % should show "Not installed" in the local section (not error).
            output = evalc('try; mip.info(''mip-org/test-channel1/alpha''); catch; end');
            testCase.verifyTrue(contains(output, 'Not installed'), ...
                'Info should indicate package is not installed locally');
        end

        function testInfoShowsLoadedStatus(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg');
            mip.load('mip-org/core/mypkg');

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'Loaded: Yes'), ...
                'Info should show loaded status');
        end

        function testInfoShowsNotLoadedStatus(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg');

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'Loaded: No'), ...
                'Info should show not loaded status');
        end

        function testInfoShowsDependencies(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg', ...
                'dependencies', {'depA', 'depB'});

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'depA'), ...
                'Info should list dependencies');
            testCase.verifyTrue(contains(output, 'depB'), ...
                'Info should list all dependencies');
        end

        function testInfoShowsNoDependencies(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg');

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'Dependencies: None'), ...
                'Info should show "None" when no dependencies');
        end

        %% --- Multiple installations with same bare name ---

        function testInfoBareNameShowsAllInstallations(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'sharedpkg', ...
                'version', '1.0.0');
            createTestPackage(testCase.TestRoot, 'other-org', 'extras', 'sharedpkg', ...
                'version', '2.0.0');

            output = evalc('try; mip.info(''sharedpkg''); catch; end');
            testCase.verifyTrue(contains(output, 'mip-org/core/sharedpkg'), ...
                'Info should show first installation');
            testCase.verifyTrue(contains(output, 'other-org/extras/sharedpkg'), ...
                'Info should show second installation');
            testCase.verifyTrue(contains(output, '1.0.0'), ...
                'Info should show first version');
            testCase.verifyTrue(contains(output, '2.0.0'), ...
                'Info should show second version');
        end

        %% --- Editable install info ---

        function testInfoShowsEditableFlag(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            output = evalc('try; mip.info(''local/local/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'Editable: Yes'), ...
                'Info should show editable flag for editable installs');
            testCase.verifyTrue(contains(output, 'Source:'), ...
                'Info should show source path for editable installs');
        end

        %% --- FQN vs bare name ---

        function testInfoFQNShowsOnlyThatInstallation(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'sharedpkg', ...
                'version', '1.0.0');
            createTestPackage(testCase.TestRoot, 'other-org', 'extras', 'sharedpkg', ...
                'version', '2.0.0');

            output = evalc('try; mip.info(''other-org/extras/sharedpkg''); catch; end');
            % Should show only the FQN-specified installation in local section
            testCase.verifyTrue(contains(output, 'other-org/extras/sharedpkg'), ...
                'Should show the requested FQN installation');
            testCase.verifyTrue(contains(output, '2.0.0'), ...
                'Should show version of requested installation');
        end

        %% --- Local install section header ---

        function testInfoShowsLocalInstallationHeader(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg');

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'Local Installation'), ...
                'Info should have a Local Installation section');
        end

        function testInfoShowsRemoteChannelHeader(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg');

            output = evalc('try; mip.info(''mip-org/core/mypkg''); catch; end');
            testCase.verifyTrue(contains(output, 'Remote Channel'), ...
                'Info should have a Remote Channel section');
        end

        %% --- Unknown package error ---

        function testInfoErrorsForUnknownPackage(testCase)
            % A package that is not installed and not in any channel should
            % throw an error.
            testCase.verifyError(@() mip.info('nonexistent_pkg_xyz'), ...
                'mip:unknownPackage');
        end

        function testInfoErrorsForUnknownFQN(testCase)
            testCase.verifyError(@() mip.info('mip-org/core/nonexistent_pkg_xyz'), ...
                'mip:unknownPackage');
        end

        function testInfoErrorsForUnknownPackageInChannel(testCase)
            testCase.verifyError( ...
                @() mip.info('--channel', 'mip-org/test-channel1', 'nonexistent_pkg_xyz'), ...
                'mip:unknownPackage');
        end

    end
end
