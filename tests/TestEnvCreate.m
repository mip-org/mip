classdef TestEnvCreate < matlab.unittest.TestCase
%TESTENVCREATE   Tests for "mip env create" (MEP 8).

    properties
        OrigMipRoot
        OrigDir
        TestRoot
        WorkDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigDir = pwd;
            testCase.TestRoot = [tempname '_mip_env_create_root'];
            testCase.WorkDir = [tempname '_mip_env_create_work'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigDir);
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.WorkDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            if exist(testCase.WorkDir, 'dir')
                rmdir(testCase.WorkDir, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testCreateNamedGoesToBaselineStore(testCase)
            output = evalc('mip.env(''create'', ''scratch'')');
            envDir = fullfile(testCase.TestRoot, 'envs', 'scratch');
            testCase.verifyTrue(isfolder(fullfile(envDir, 'packages')), ...
                'Named env should be created in <baseline root>/envs/ with a packages/ subtree');
            testCase.verifyTrue(contains(output, 'Created environment'), ...
                'Should print the created path');
            testCase.verifyTrue(contains(output, 'mip activate scratch'), ...
                'Should print an activation hint');
        end

        function testCreateInvalidNameErrors(testCase)
            testCase.verifyError(@() mip.env('create', 'bad.name'), ...
                'mip:env:invalidName');
            testCase.verifyError(@() mip.env('create', '-scratch'), ...
                'mip:env:invalidName');
        end

        function testCreateNoArgCreatesDotMipInCwd(testCase)
            cd(testCase.WorkDir);
            evalc('mip.env(''create'')');
            testCase.verifyTrue(isfolder(fullfile(testCase.WorkDir, '.mip', 'packages')), ...
                'No-arg create should create ./.mip in the current directory');
        end

        function testCreateNoArgRefusesLockfileDir(testCase)
            cd(testCase.WorkDir);
            fid = fopen(fullfile(testCase.WorkDir, 'mip.lock'), 'w');
            fclose(fid);
            testCase.verifyError(@() mip.env('create'), ...
                'mip:env:lockfilePresent');
            testCase.verifyFalse(isfolder(fullfile(testCase.WorkDir, '.mip')), ...
                '.mip must not be created when mip.lock is present');
        end

        function testCreatePathTarget(testCase)
            target = fullfile(testCase.WorkDir, 'myenv');
            evalc('mip.env(''create'', target)');
            testCase.verifyTrue(isfolder(fullfile(target, 'packages')));
        end

        function testCreateExistingEnvErrors(testCase)
            target = fullfile(testCase.WorkDir, 'myenv');
            evalc('mip.env(''create'', target)');
            testCase.verifyError(@() mip.env('create', target), ...
                'mip:env:alreadyExists');
        end

        function testCreateNonEmptyDirErrors(testCase)
            target = fullfile(testCase.WorkDir, 'notempty');
            mkdir(target);
            fid = fopen(fullfile(target, 'somefile.txt'), 'w');
            fclose(fid);
            testCase.verifyError(@() mip.env('create', target), ...
                'mip:env:directoryNotEmpty');
        end

        function testCreateEmptyExistingDirOk(testCase)
            target = fullfile(testCase.WorkDir, 'emptydir');
            mkdir(target);
            evalc('mip.env(''create'', target)');
            testCase.verifyTrue(isfolder(fullfile(target, 'packages')));
        end

        function testCreateNamedWhileEnvActiveUsesBaselineStore(testCase)
            % Named env operations always resolve against the baseline
            % store, even while another env is active.
            evalc('mip.env(''create'', ''first'')');
            evalc('mip.env(''activate'', ''first'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));

            evalc('mip.env(''create'', ''second'')');
            testCase.verifyTrue(isfolder(fullfile(testCase.TestRoot, ...
                'envs', 'second', 'packages')), ...
                'Named create while active must anchor to the baseline store');
            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, ...
                'envs', 'first', 'envs')), ...
                'The active env must not grow its own envs/ store');
        end

    end
end
