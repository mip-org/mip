classdef TestBrokenDependencyWarning < matlab.unittest.TestCase
%TESTBROKENDEPENDENCYWARNING   Tests for mip.state.check_broken_dependencies.

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

        %% Installed mode tests

        function testInstalled_NoBrokenDeps(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'mip-org/core/depA'});
            % Should not warn
            testCase.verifyWarningFree( ...
                @() mip.state.check_broken_dependencies('installed'));
        end

        function testInstalled_BrokenFqnDep(testCase)
            % mainpkg depends on depA (FQN), but depA is not installed
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'mip-org/core/depA'});
            testCase.verifyWarning( ...
                @() mip.state.check_broken_dependencies('installed'), ...
                'mip:brokenDependencies');
        end

        function testInstalled_BrokenBareDep(testCase)
            % mainpkg depends on depA (bare name), but depA is not installed anywhere
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            testCase.verifyWarning( ...
                @() mip.state.check_broken_dependencies('installed'), ...
                'mip:brokenDependencies');
        end

        function testInstalled_NoDepsNoBroken(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'standalone');
            testCase.verifyWarningFree( ...
                @() mip.state.check_broken_dependencies('installed'));
        end

        function testInstalled_NoPackages(testCase)
            testCase.verifyWarningFree( ...
                @() mip.state.check_broken_dependencies('installed'));
        end

        %% Loaded mode tests

        function testLoaded_NoBrokenDeps(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            mip.load('mip-org/core/mainpkg');
            testCase.verifyWarningFree( ...
                @() mip.state.check_broken_dependencies('loaded'));
        end

        function testLoaded_BrokenDep(testCase)
            % Set up: mainpkg is loaded and depends on depA, but depA is not loaded
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            % Manually mark mainpkg as loaded without loading depA
            mip.state.key_value_append('MIP_LOADED_PACKAGES', 'mip-org/core/mainpkg');
            testCase.verifyWarning( ...
                @() mip.state.check_broken_dependencies('loaded'), ...
                'mip:brokenDependencies');
        end

        function testLoaded_NoPackages(testCase)
            testCase.verifyWarningFree( ...
                @() mip.state.check_broken_dependencies('loaded'));
        end

    end
end
