classdef TestMipRoot < matlab.unittest.TestCase
%TESTMIPROOT   Tests for mip.paths.root() and MIP_ROOT environment variable
%   handling, including validation of nonexistent paths and missing
%   'packages' subdirectories.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
        end
    end

    methods (Test)

        function testValidMipRoot(testCase)
            % MIP_ROOT pointing to a directory with a 'packages' subdir
            % should be returned as-is.
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.verifyEqual(mip.paths.root(), testCase.TestRoot);
        end

        function testNonexistentPathErrors(testCase)
            % MIP_ROOT pointing to a path that does not exist should error.
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.verifyError(@() mip.paths.root(), 'mip:rootInvalid');
        end

        function testPathIsFileErrors(testCase)
            % MIP_ROOT pointing to a regular file (not a directory) should
            % error.
            fid = fopen(testCase.TestRoot, 'w');
            fwrite(fid, 'not a dir');
            fclose(fid);
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.verifyError(@() mip.paths.root(), 'mip:rootInvalid');
            delete(testCase.TestRoot);
        end

        function testMissingPackagesSubdirErrors(testCase)
            % MIP_ROOT pointing to an existing directory without a
            % 'packages' subdirectory should error (not auto-create).
            mkdir(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.verifyError(@() mip.paths.root(), 'mip:rootInvalid');
            % Verify packages dir was not auto-created
            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, 'packages')));
        end

        function testEmptyStringTreatedAsUnset(testCase)
            % MIP_ROOT="" should behave the same as unset (fall through to
            % path-based detection). We can't easily verify the resulting
            % path here, but we can verify that mip.paths.root() does not
            % raise a 'mip:rootInvalid' error (which would indicate the
            % empty string was being validated as a path).
            setenv('MIP_ROOT', '');
            try
                mip.paths.root();
            catch ME
                testCase.verifyNotEqual(ME.identifier, 'mip:rootInvalid', ...
                    'Empty MIP_ROOT should be treated as unset, not validated as a path');
            end
        end

    end
end
