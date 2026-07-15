classdef TestEnvCommand < matlab.unittest.TestCase
%TESTENVCOMMAND   Tests for the "mip env" object commands
%   (create / list / delete / show) and environment argument handling.

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
        WorkDir
        OrigPwd
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_env_test'];
            testCase.WorkDir = [tempname '_mip_env_cwd'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            setenv('MIP_CONFIRM', '');
            testCase.OrigPwd = pwd;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigPwd);
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            setenv('MIP_CONFIRM', testCase.OrigMipConfirm);
            for d = {testCase.TestRoot, testCase.WorkDir}
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        % ---- create ----

        function testCreateNamed(testCase)
            output = evalc('mip.env.create(''scratch'')');

            envPath = fullfile(testCase.TestRoot, 'envs', 'scratch');
            testCase.verifyTrue(isfolder(fullfile(envPath, 'packages')), ...
                'create should materialize an empty packages/ subtree');
            markerPath = fullfile(envPath, 'mip-env.json');
            testCase.verifyTrue(isfile(markerPath), ...
                'create should write the mip-env.json marker');
            marker = jsondecode(fileread(markerPath));
            testCase.verifyEqual(marker.format_version, 1);
            testCase.verifyEqual(marker.mip_version, mip.version());
            testCase.verifyTrue(isfield(marker, 'created'));
            testCase.verifyTrue(contains(output, 'mip activate scratch'), ...
                'create should print an activation hint');
        end

        function testCreateInvalidNameErrors(testCase)
            testCase.verifyError(@() mip.env.create('bad.name'), ...
                'mip:env:invalidName');
            testCase.verifyError(@() mip.env.create('-bad'), ...
                'mip:env:invalidName');
        end

        function testCreateExistingEnvErrors(testCase)
            mip.env.create('scratch');
            testCase.verifyError(@() mip.env.create('scratch'), ...
                'mip:env:alreadyExists');
        end

        function testCreateNonEmptyDirErrors(testCase)
            target = fullfile(testCase.WorkDir, 'occupied');
            mkdir(target);
            fid = fopen(fullfile(target, 'somefile.txt'), 'w');
            fwrite(fid, 'x');
            fclose(fid);

            testCase.verifyError(@() mip.env.create(target), ...
                'mip:env:directoryNotEmpty');
        end

        function testCreateEmptyExistingDirOk(testCase)
            target = fullfile(testCase.WorkDir, 'empty');
            mkdir(target);

            mip.env.create(target);

            testCase.verifyTrue(mip.env.is_env(target));
            testCase.verifyTrue(isfolder(fullfile(target, 'packages')));
        end

        function testCreateNoArgCreatesDotMipInCwd(testCase)
            cd(testCase.WorkDir);
            mip.env.create();

            envPath = fullfile(testCase.WorkDir, '.mip');
            testCase.verifyTrue(mip.env.is_env(envPath));
            testCase.verifyTrue(isfolder(fullfile(envPath, 'packages')));
        end

        function testCreateNoArgErrorsOnMipLock(testCase)
            cd(testCase.WorkDir);
            fid = fopen(fullfile(testCase.WorkDir, 'mip.lock'), 'w');
            fwrite(fid, '{}');
            fclose(fid);

            testCase.verifyError(@() mip.env.create(), ...
                'mip:env:lockfilePresent');
        end

        function testCreateRelativePathStoredAbsolute(testCase)
            cd(testCase.WorkDir);
            output = evalc('mip.env.create(''./subenv'')');

            envPath = fullfile(testCase.WorkDir, 'subenv');
            testCase.verifyTrue(mip.env.is_env(envPath), ...
                'relative path arg should create relative to cwd');
            testCase.verifyTrue(contains(output, testCase.WorkDir), ...
                'created path should be reported absolute');
        end

        % ---- list ----

        function testListEmpty(testCase)
            output = evalc('mip.env.list()');
            testCase.verifyTrue(contains(output, 'No named environments'));
        end

        function testListShowsNamedAndMarksActive(testCase)
            mip.env.create('alpha');
            mip.env.create('beta');
            % A non-env directory in the store is ignored.
            mkdir(fullfile(testCase.TestRoot, 'envs', 'junk'));
            mip.activate('beta');

            output = evalc('mip.env.list()');

            testCase.verifyTrue(contains(output, 'alpha'));
            testCase.verifyTrue(contains(output, '* beta'), ...
                'active environment should be marked');
            testCase.verifyFalse(contains(output, 'junk'), ...
                'entries without a marker should be ignored');
        end

        % ---- delete ----

        function testDeletePathErrors(testCase)
            testCase.verifyError(@() mip.env.delete('./someenv'), ...
                'mip:env:pathDelete');
        end

        function testDeleteMissingErrors(testCase)
            testCase.verifyError(@() mip.env.delete('nosuch'), ...
                'mip:env:notFound');
        end

        function testDeleteRefusesNonEnvDir(testCase)
            mkdir(fullfile(testCase.TestRoot, 'envs', 'fake'));
            testCase.verifyError(@() mip.env.delete('fake'), ...
                'mip:env:notAnEnvironment');
        end

        function testDeleteRefusesActiveEnv(testCase)
            mip.env.create('scratch');
            mip.activate('scratch');
            testCase.verifyError(@() mip.env.delete('scratch'), ...
                'mip:env:deleteActive');
        end

        function testDeleteAbortsWhenNotConfirmed(testCase)
            mip.env.create('scratch');
            setenv('MIP_CONFIRM', 'no');

            output = evalc('mip.env.delete(''scratch'')');

            testCase.verifyTrue(contains(output, 'aborted'));
            testCase.verifyTrue(isfolder(fullfile(testCase.TestRoot, 'envs', 'scratch')));
        end

        function testDeleteWithMipConfirm(testCase)
            mip.env.create('scratch');
            setenv('MIP_CONFIRM', 'yes');

            mip.env.delete('scratch');

            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, 'envs', 'scratch')));
        end

        function testDeleteWithYesFlag(testCase)
            mip.env.create('scratch');

            mip.env.delete('scratch', '--yes');

            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, 'envs', 'scratch')));
        end

        % ---- show / dispatcher ----

        function testShowNoActiveEnv(testCase)
            output = evalc('mip.env.show()');
            testCase.verifyTrue(contains(output, 'No environment is active'));
        end

        function testShowActiveEnv(testCase)
            mip.env.create('scratch');
            mip.activate('scratch');

            output = evalc('mip.env.show()');

            testCase.verifyTrue(contains(output, 'active environment: scratch'));
        end

        function testDispatcherUnknownSubcommand(testCase)
            testCase.verifyError(@() mip.env('bogus'), ...
                'mip:unknownSubcommand');
        end

        function testDispatcherBareShowsActive(testCase)
            output = evalc('mip(''env'')');
            testCase.verifyTrue(contains(output, 'No environment is active'));
        end

    end
end
