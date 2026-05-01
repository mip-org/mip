classdef TestPathTraversal < matlab.unittest.TestCase
%TESTPATHTRAVERSAL   Integration test for mip-org/mip#230.
% A package whose mip.json declares paths that escape the package source
% directory must be rejected, not addpath'd. Same for --addpath/--rmpath.

    properties
        OrigMipRoot
        TestRoot
        SavedPath
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_traversal_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.SavedPath = path;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            path(testCase.SavedPath);
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testLoad_RejectsParentEscapeInMipJsonPaths(testCase)
            pkgDir = fullfile(testCase.TestRoot, 'packages', 'gh', ...
                              'mip-org', 'core', 'evil');
            mkdir(fullfile(pkgDir, 'evil'));
            jsonText = ['{"name":"evil","version":"1.0.0","architecture":"any",' ...
                        '"install_type":"test","dependencies":[],' ...
                        '"paths":["../../../../etc"]}'];
            fid = fopen(fullfile(pkgDir, 'mip.json'), 'w');
            fwrite(fid, jsonText);
            fclose(fid);

            testCase.verifyError( ...
                @() mip.load('mip-org/core/evil'), 'mip:unsafePath');
        end

        function testLoad_RejectsParentEscapeInAddpathFlag(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            testCase.verifyError( ...
                @() mip.load('foo', '--addpath', '../../..'), ...
                'mip:unsafePath');
        end

    end
end
