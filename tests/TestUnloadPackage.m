classdef TestUnloadPackage < matlab.unittest.TestCase
%TESTUNLOADPACKAGE   Tests for mip.unload functionality.

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

        function testUnloadPackage_Basic(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/testpkg'));

            mip.unload('mip-org/core/testpkg');
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/testpkg'));
        end

        function testUnloadPackage_RemovesFromPath(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue(ismember(pkgDir, strsplit(path, pathsep)));

            mip.unload('mip-org/core/testpkg');
            testCase.verifyFalse(ismember(pkgDir, strsplit(path, pathsep)));
        end

        function testUnloadPackage_RemovesFromAllLists(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg', '--sticky');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/testpkg'));
            testCase.verifyTrue(mip.utils.is_directly_loaded('mip-org/core/testpkg'));
            testCase.verifyTrue(mip.utils.is_sticky('mip-org/core/testpkg'));

            mip.unload('mip-org/core/testpkg');
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/testpkg'));
            testCase.verifyFalse(mip.utils.is_directly_loaded('mip-org/core/testpkg'));
            testCase.verifyFalse(mip.utils.is_sticky('mip-org/core/testpkg'));
        end

        function testUnloadPackage_NotLoaded(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            % Should print message but not error
            mip.unload('mip-org/core/testpkg');
        end

        function testUnloadPackage_CannotUnloadMip(testCase)
            testCase.verifyError(@() mip.unload('mip-org/core/mip'), ...
                'mip:cannotUnloadMip');
        end

        function testUnloadAll_SkipsSticky(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'stickypkg');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'normalpkg');

            mip.load('mip-org/core/stickypkg', '--sticky');
            mip.load('mip-org/core/normalpkg');

            mip.unload('--all');

            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/stickypkg'));
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/normalpkg'));
        end

        function testUnloadAll_Force(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'stickypkg');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'normalpkg');

            mip.load('mip-org/core/stickypkg', '--sticky');
            mip.load('mip-org/core/normalpkg');

            mip.unload('--all', '--force');

            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/stickypkg'));
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/normalpkg'));
        end

        function testUnloadAll_NeverUnloadsMipItself(testCase)
            % Set up mip as loaded and sticky (as mip.m does)
            mip.utils.key_value_append('MIP_LOADED_PACKAGES', 'mip-org/core/mip');
            mip.utils.key_value_append('MIP_STICKY_PACKAGES', 'mip-org/core/mip');

            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');

            mip.unload('--all', '--force');

            % mip should still be loaded
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/mip'));
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/testpkg'));
        end

        function testUnloadPackage_PrunesUnusedDependencies(testCase)
            % depA is loaded as a dependency of mainpkg
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});

            mip.load('mip-org/core/mainpkg');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/depA'));

            % Unloading mainpkg should also prune depA
            mip.unload('mip-org/core/mainpkg');
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/mainpkg'));
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/depA'));
        end

        function testUnloadPackage_DoesNotPruneSharedDeps(testCase)
            % depA is shared by mainpkg1 and mainpkg2
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg1', ...
                'dependencies', {'depA'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg2', ...
                'dependencies', {'depA'});

            mip.load('mip-org/core/mainpkg1');
            mip.load('mip-org/core/mainpkg2');

            % Unloading mainpkg1 should NOT prune depA (still needed by mainpkg2)
            mip.unload('mip-org/core/mainpkg1');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/depA'));
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/mainpkg2'));
        end

        function testUnloadPackage_BareName(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            mip.unload('testpkg');
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/testpkg'));
        end

        function testUnloadBareName_AmbiguousUnloadsMostRecent(testCase)
            % When bare name matches multiple loaded packages,
            % unload the most recently loaded one
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'duppkg');
            createTestPackage(testCase.TestRoot, 'other-org', 'extras', 'duppkg');

            % Load core first, then extras (extras is most recent)
            mip.load('mip-org/core/duppkg');
            mip.load('other-org/extras/duppkg');

            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/duppkg'));
            testCase.verifyTrue(mip.utils.is_loaded('other-org/extras/duppkg'));

            % Unloading bare name should unload the most recently loaded one
            mip.unload('duppkg');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/duppkg'), ...
                'Earlier loaded package should remain');
            testCase.verifyFalse(mip.utils.is_loaded('other-org/extras/duppkg'), ...
                'Most recently loaded package should be unloaded');
        end

        function testUnloadBareName_AmbiguousRespectsLoadOrder(testCase)
            % Verify it is load order, not alphabetical or mip-org priority
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'duppkg');
            createTestPackage(testCase.TestRoot, 'other-org', 'extras', 'duppkg');

            % Load extras first, then core (core is most recent)
            mip.load('other-org/extras/duppkg');
            mip.load('mip-org/core/duppkg');

            % Unloading bare name should unload core (most recent), not extras
            mip.unload('duppkg');
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/duppkg'), ...
                'Most recently loaded (core) should be unloaded');
            testCase.verifyTrue(mip.utils.is_loaded('other-org/extras/duppkg'), ...
                'Earlier loaded (extras) should remain');
        end

    end
end
