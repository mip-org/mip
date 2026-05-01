classdef TestInfoSelf < matlab.unittest.TestCase
%TESTINFOSELF   Tests for `mip info` with no arguments, which prints
%   information about mip itself (version, root, architecture).

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_info_self_test'];
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

        function testNoArgsShowsVersion(testCase)
            % Output should include the mip version string.
            output = evalc('mip.info()');
            testCase.verifyTrue(contains(output, mip.version()), ...
                'mip info (no args) should show the mip version');
        end

        function testNoArgsShowsRoot(testCase)
            % Output should include the resolved mip root directory.
            output = evalc('mip.info()');
            testCase.verifyTrue(contains(output, testCase.TestRoot), ...
                'mip info (no args) should show the mip root directory');
        end

        function testNoArgsShowsArch(testCase)
            % Output should include the current architecture tag.
            output = evalc('mip.info()');
            testCase.verifyTrue(contains(output, mip.build.arch()), ...
                'mip info (no args) should show the architecture tag');
        end

    end
end
