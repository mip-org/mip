classdef TestEnvListDelete < matlab.unittest.TestCase
%TESTENVLISTDELETE   Tests for "mip env list" and "mip env delete" (MEP 8).

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_env_listdel_root'];
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

        function testListEmpty(testCase)
            output = evalc('mip.env(''list'')');
            testCase.verifyTrue(contains(output, 'No named environments'));
        end

        function testListShowsEnvsAndIgnoresNonEnvs(testCase)
            evalc('mip.env(''create'', ''alpha'')');
            evalc('mip.env(''create'', ''beta'')');
            % A stray non-env entry in the store is ignored.
            mkdir(fullfile(testCase.TestRoot, 'envs', 'junk'));

            output = evalc('mip.env(''list'')');
            testCase.verifyTrue(contains(output, 'alpha'));
            testCase.verifyTrue(contains(output, 'beta'));
            testCase.verifyFalse(contains(output, 'junk'), ...
                'Entries without a packages/ subtree must be ignored');
        end

        function testListMarksActive(testCase)
            evalc('mip.env(''create'', ''alpha'')');
            evalc('mip.env(''create'', ''beta'')');
            evalc('mip.env(''activate'', ''beta'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));

            output = evalc('mip.env(''list'')');
            testCase.verifyTrue(contains(output, '* beta'), ...
                'The active env should be marked');
            testCase.verifyFalse(contains(output, '* alpha'));
        end

        function testDeleteRefusesPathArg(testCase)
            testCase.verifyError(@() mip.env('delete', './someenv'), ...
                'mip:env:pathDelete');
        end

        function testDeleteNotFound(testCase)
            testCase.verifyError(@() mip.env('delete', 'ghost', '--yes'), ...
                'mip:env:notFound');
        end

        function testDeleteRefusesNonEnvDir(testCase)
            mkdir(fullfile(testCase.TestRoot, 'envs', 'junk'));
            testCase.verifyError(@() mip.env('delete', 'junk', '--yes'), ...
                'mip:env:notAnEnvironment');
        end

        function testDeleteConfirmYes(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            setenv('MIP_CONFIRM', 'yes');
            evalc('mip.env(''delete'', ''scratch'')');
            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, 'envs', 'scratch')));
        end

        function testDeleteConfirmNoAborts(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            setenv('MIP_CONFIRM', 'no');
            output = evalc('mip.env(''delete'', ''scratch'')');
            testCase.verifyTrue(contains(output, 'aborted'));
            testCase.verifyTrue(isfolder(fullfile(testCase.TestRoot, ...
                'envs', 'scratch', 'packages')), ...
                'Declining the confirmation must leave the env intact');
        end

        function testDeleteYesFlagSkipsConfirm(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            setenv('MIP_CONFIRM', '');  % unset: a prompt would block here
            evalc('mip.env(''delete'', ''scratch'', ''--yes'')');
            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, 'envs', 'scratch')));
        end

        function testDeleteRefusesActiveEnv(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));
            testCase.verifyError(@() mip.env('delete', 'scratch', '--yes'), ...
                'mip:env:deleteActive');
        end

    end
end
