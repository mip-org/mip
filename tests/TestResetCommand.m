classdef TestResetCommand < matlab.unittest.TestCase
%TESTRESETCOMMAND   Tests for mip.reset functionality.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
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

        function testReset_UnloadsAllPackages(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgB');
            mip.load('mip-org/core/pkgA', '--sticky');
            mip.load('mip-org/core/pkgB');

            mip.reset();

            testCase.verifyFalse(mip.state.is_loaded('mip-org/core/pkgA'));
            testCase.verifyFalse(mip.state.is_loaded('mip-org/core/pkgB'));
        end

        function testReset_ClearsAllKeyValueStores(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            mip.load('mip-org/core/pkgA', '--sticky');
            % Stand in for a test context that outlived its `mip test` run.
            mip.state.key_value_set('MIP_TEST_CONTEXT', 'gh/mip-org/core/pkgA');

            mip.reset();

            testCase.verifyFalse(isappdata(0, 'MIP_LOADED_PACKAGES'));
            testCase.verifyFalse(isappdata(0, 'MIP_DIRECTLY_LOADED_PACKAGES'));
            testCase.verifyFalse(isappdata(0, 'MIP_STICKY_PACKAGES'));
            testCase.verifyFalse(isappdata(0, 'MIP_TEST_CONTEXT'));
        end

        function testReset_DeactivatesActiveEnv(testCase)
            mip.env.create('scratch');
            mip.activate('scratch');
            testCase.assertEqual(getenv('MIP_ROOT'), ...
                fullfile(testCase.TestRoot, 'envs', 'scratch'));

            mip.reset();

            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot, ...
                'MIP_ROOT should be restored to the baseline root');
            testCase.verifyEmpty(mip.state.get_active_env());
            testCase.verifyFalse(isappdata(0, 'MIP_ACTIVE_ENV'));
        end

        function testReset_WorksWhenNothingLoaded(testCase)
            % Should not error when no packages are loaded
            mip.reset();

            testCase.verifyFalse(isappdata(0, 'MIP_LOADED_PACKAGES'));
            testCase.verifyFalse(isappdata(0, 'MIP_DIRECTLY_LOADED_PACKAGES'));
            testCase.verifyFalse(isappdata(0, 'MIP_STICKY_PACKAGES'));
        end

        function testReset_RemovesFromPath(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            srcDir = fullfile(pkgDir, 'pkgA');
            mip.load('mip-org/core/pkgA');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));

            mip.reset();

            testCase.verifyFalse(ismember(srcDir, strsplit(path, pathsep)));
        end

    end
end
