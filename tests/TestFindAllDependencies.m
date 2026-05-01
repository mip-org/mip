classdef TestFindAllDependencies < matlab.unittest.TestCase
%TESTFINDALLDEPENDENCIES   Tests for mip.dependency.find_all_dependencies.

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
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testNoDependencies(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'leaf');
            deps = mip.dependency.find_all_dependencies('gh/mip-org/core/leaf');
            testCase.verifyEmpty(deps);
        end

        function testTransitiveDependencies(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'a', ...
                'dependencies', {'b'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'b', ...
                'dependencies', {'c'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'c');

            deps = mip.dependency.find_all_dependencies('gh/mip-org/core/a');
            testCase.verifyEqual(sort(deps), ...
                {'gh/mip-org/core/b', 'gh/mip-org/core/c'});
        end

        function testDirectCircularDependency(testCase)
            % A -> B -> A. Must terminate without stack exhaustion. The
            % entry FQN is excluded from results.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'a', ...
                'dependencies', {'b'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'b', ...
                'dependencies', {'a'});

            deps = mip.dependency.find_all_dependencies('gh/mip-org/core/a');
            testCase.verifyEqual(sort(deps), {'gh/mip-org/core/b'});
        end

        function testSelfCircularDependency(testCase)
            % A -> A. Must terminate.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'a', ...
                'dependencies', {'a'});

            deps = mip.dependency.find_all_dependencies('gh/mip-org/core/a');
            testCase.verifyEmpty(deps);
        end

        function testIndirectCircularDependency(testCase)
            % A -> B -> C -> A. Must terminate. Entry FQN is excluded.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'a', ...
                'dependencies', {'b'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'b', ...
                'dependencies', {'c'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'c', ...
                'dependencies', {'a'});

            deps = mip.dependency.find_all_dependencies('gh/mip-org/core/a');
            testCase.verifyEqual(sort(deps), ...
                {'gh/mip-org/core/b', 'gh/mip-org/core/c'});
        end

        function testDiamondDependency(testCase)
            % A -> B, A -> C, B -> D, C -> D. Should not duplicate D.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'a', ...
                'dependencies', {'b', 'c'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'b', ...
                'dependencies', {'d'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'c', ...
                'dependencies', {'d'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'd');

            deps = mip.dependency.find_all_dependencies('gh/mip-org/core/a');
            testCase.verifyEqual(sort(deps), ...
                {'gh/mip-org/core/b', 'gh/mip-org/core/c', 'gh/mip-org/core/d'});
        end

    end
end
