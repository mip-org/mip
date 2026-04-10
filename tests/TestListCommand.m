classdef TestListCommand < matlab.unittest.TestCase
%TESTLISTCOMMAND   Tests for mip.list functionality.

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

        function testList_NoPackages(testCase)
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, 'No packages installed'));
        end

        function testList_ShowsInstalledPackage(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, 'alpha'));
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
        end

        function testList_ShowsLoadedPackagesSection(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.load('mip-org/core/alpha');
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, 'Loaded Packages'));
        end

        function testList_ShowsNotLoadedSection(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            mip.load('mip-org/core/alpha');
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, 'Other Installed Packages'));
            testCase.verifyTrue(contains(output, 'beta'));
        end

        function testList_DirectlyLoadedMarkedWithAsterisk(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.load('mip-org/core/alpha');
            output = evalc('mip.list()');
            % The directly loaded package should have a * prefix
            testCase.verifyTrue(contains(output, '*'));
        end

        function testList_StickyMarker(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.load('mip-org/core/alpha', '--sticky');
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, '[sticky]'));
        end

        function testList_ShowsVersion(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha', ...
                'version', '3.2.1');
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, '3.2.1'));
        end

        function testList_SortByName(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'charlie');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'bravo');
            mip.load('mip-org/core/charlie');
            mip.load('mip-org/core/alpha');
            mip.load('mip-org/core/bravo');
            output = evalc('mip.list(''--sort-by-name'')');
            % With --sort-by-name, alpha should appear before bravo, bravo before charlie
            posAlpha = strfind(output, 'alpha');
            posBravo = strfind(output, 'bravo');
            posCharlie = strfind(output, 'charlie');
            testCase.verifyTrue(posAlpha(1) < posBravo(1));
            testCase.verifyTrue(posBravo(1) < posCharlie(1));
        end

        function testList_MultiplePackages(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'gamma');
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, 'alpha'));
            testCase.verifyTrue(contains(output, 'beta'));
            testCase.verifyTrue(contains(output, 'gamma'));
        end

    end
end
