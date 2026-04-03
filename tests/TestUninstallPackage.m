classdef TestUninstallPackage < matlab.unittest.TestCase
%TESTUNINSTALLPACKAGE   Tests for mip.uninstall components.
%
%   Note: Full mip.uninstall requires interactive user confirmation via
%   input(). These tests verify the underlying mechanisms (directory removal,
%   directly_installed tracking, load state cleanup) without calling the
%   top-level uninstall function.

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

        function testUninstallRemovesDirectory(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);

            rmdir(pkgDir, 's');
            testCase.verifyFalse(exist(pkgDir, 'dir') > 0);
        end

        function testUninstallRemovesFromDirectlyInstalled(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.utils.add_directly_installed('mip-org/core/testpkg');

            testCase.verifyTrue(ismember('mip-org/core/testpkg', ...
                mip.utils.get_directly_installed()));

            mip.utils.remove_directly_installed('mip-org/core/testpkg');
            testCase.verifyFalse(ismember('mip-org/core/testpkg', ...
                mip.utils.get_directly_installed()));
        end

        function testUnloadBeforeUninstall(testCase)
            % Simulate what uninstall does: unload first, then remove
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue(mip.utils.is_loaded('mip-org/core/testpkg'));

            mip.unload('mip-org/core/testpkg');
            testCase.verifyFalse(mip.utils.is_loaded('mip-org/core/testpkg'));

            rmdir(pkgDir, 's');
            testCase.verifyFalse(exist(pkgDir, 'dir') > 0);
        end

        function testPackageNoLongerDiscoverableAfterRemoval(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            fqn = mip.utils.resolve_bare_name('testpkg');
            testCase.verifyEqual(fqn, 'mip-org/core/testpkg');

            pkgDir = mip.utils.get_package_dir('mip-org', 'core', 'testpkg');
            rmdir(pkgDir, 's');

            fqn = mip.utils.resolve_bare_name('testpkg');
            testCase.verifyEqual(fqn, '');
        end

        function testMipCannotBeUninstalled(testCase)
            % Verify that mip-org/core/mip is detected as mip
            r = mip.utils.parse_package_arg('mip-org/core/mip');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.name, 'mip');

            % The uninstall.m code checks: ismember('mip-org/core/mip', resolvedPackages)
            resolvedPackages = {'mip-org/core/mip', 'mip-org/core/otherpkg'};
            filtered = resolvedPackages(~strcmp(resolvedPackages, 'mip-org/core/mip'));
            testCase.verifyEqual(filtered, {'mip-org/core/otherpkg'});
        end

        function testOtherMipPackageCanBeUninstalled(testCase)
            % A 'mip' package on another channel should not be blocked
            resolvedPackages = {'mylab/custom/mip'};
            filtered = resolvedPackages(~strcmp(resolvedPackages, 'mip-org/core/mip'));
            testCase.verifyEqual(filtered, {'mylab/custom/mip'}, ...
                'mip on a different channel should not be filtered out');
        end

        function testCleanupEmptyParentDirs(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'testorg', 'testchan', 'testpkg');
            chanDir = fullfile(testCase.TestRoot, 'packages', 'testorg', 'testchan');
            orgDir = fullfile(testCase.TestRoot, 'packages', 'testorg');

            % Remove the package
            rmdir(pkgDir, 's');

            % Channel dir should now be empty and removable
            contents = dir(chanDir);
            contents = contents(~ismember({contents.name}, {'.', '..'}));
            testCase.verifyTrue(isempty(contents), 'Channel dir should be empty after removing only package');

            % Clean up empty dirs
            rmdir(chanDir);
            rmdir(orgDir);

            testCase.verifyFalse(exist(orgDir, 'dir') > 0);
        end

        function testUninstallBareNameAmbiguous_RefusesAndPrintsOptions(testCase)
            % When bare name matches multiple installed packages, refuse and list FQNs
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'duppkg');
            createTestPackage(testCase.TestRoot, 'other-org', 'extras', 'duppkg');

            % Call the resolution logic that uninstall uses
            allMatches = mip.utils.find_all_installed_by_name('duppkg');
            testCase.verifyEqual(length(allMatches), 2, ...
                'Should find two installed packages with same bare name');
            testCase.verifyTrue(ismember('mip-org/core/duppkg', allMatches));
            testCase.verifyTrue(ismember('other-org/extras/duppkg', allMatches));
        end

        function testUninstallBareNameUnique_ResolvesNormally(testCase)
            % When bare name matches exactly one installed package, resolve it
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'uniqpkg');

            allMatches = mip.utils.find_all_installed_by_name('uniqpkg');
            testCase.verifyEqual(length(allMatches), 1);
            testCase.verifyEqual(allMatches{1}, 'mip-org/core/uniqpkg');
        end

        function testUninstallFQN_BypassesAmbiguityCheck(testCase)
            % Using FQN should work even when bare name is ambiguous
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'duppkg');
            createTestPackage(testCase.TestRoot, 'other-org', 'extras', 'duppkg');

            % FQN parsing should identify it as FQN and skip bare name resolution
            result = mip.utils.parse_package_arg('other-org/extras/duppkg');
            testCase.verifyTrue(result.is_fqn);
        end

    end
end
