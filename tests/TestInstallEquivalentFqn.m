classdef TestInstallEquivalentFqn < matlab.unittest.TestCase
%TESTINSTALLEQUIVALENTFQN   mip install rejects a package whose FQN is
%   equivalent (same org/channel, name matches under mip.name.match) to
%   one that is already installed.
%
% Equivalence equates case and treats `-`/`_` as the same character.
% The intent: prevent two parallel installs like
%   packages/user/channel/some_package/
%   packages/user/channel/some-packagE/
% from coexisting, which would happen if the underlying channel (or local
% source) hypothetically exposed both forms as distinct packages.

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_eqfqn_test'];
            testCase.SourceDir = [tempname '_mip_eqfqn_src'];
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

        function testLocalInstall_RejectsEquivalentFqn(testCase)
            % An already-installed local/local/my_pkg must block installing
            % a source dir whose mip.yaml name is 'My-Pkg'.
            createTestPackage(testCase.TestRoot, 'local', 'local', 'my_pkg');
            srcDir = createTestSourcePackage(testCase.SourceDir, 'My-Pkg');
            testCase.verifyError(@() mip.install('-e', srcDir), ...
                'mip:install:equivalentAlreadyInstalled');
        end

        function testLocalInstall_SameNameStillAlreadyInstalledMessage(testCase)
            % Sanity check: exact-same name still takes the "already
            % installed" path (no error), i.e. the new check doesn't
            % regress the existing idempotent behavior.
            createTestPackage(testCase.TestRoot, 'local', 'local', 'my_pkg');
            srcDir = createTestSourcePackage(testCase.SourceDir, 'my_pkg');
            % Should NOT throw; install_local prints a message and returns.
            mip.install('-e', srcDir);
        end

        function testRepoInstall_RejectsEquivalentFqn(testCase)
            % Pre-install user/channel/some_package on disk, then point the
            % channel index cache at a hypothetical 'some-packagE' variant
            % with the SAME org/channel. The second install must error
            % rather than create a parallel install dir.
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'some_package');

            % install.m always fetches mip-org/core first, so give it an
            % empty cached index to avoid hitting the network.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/custom', {'some-packagE'});

            testCase.verifyError( ...
                @() mip.install('mylab/custom/some-packagE'), ...
                'mip:install:equivalentAlreadyInstalled');

            % The pre-existing install is untouched, and no parallel dir
            % was created under the equivalent name.
            oldPkg = fullfile(testCase.TestRoot, 'packages', 'gh', 'mylab', 'custom', 'some_package');
            newPkg = fullfile(testCase.TestRoot, 'packages', 'gh', 'mylab', 'custom', 'some-packagE');
            testCase.verifyTrue(exist(oldPkg, 'dir') > 0);
            testCase.verifyFalse(exist(newPkg, 'dir') > 0);
        end

        function testRepoInstall_ExactNameReinstallIsNoError(testCase)
            % Sanity check: installing an already-installed exact name
            % still reports "already installed" without erroring.
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'some_package');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/custom', {'some_package'});
            mip.install('mylab/custom/some_package');
        end

    end
end
