classdef TestUninstallPackage < matlab.unittest.TestCase
%TESTUNINSTALLPACKAGE   Tests for mip.uninstall components.
%
%   These tests verify the underlying mechanisms (directory removal,
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
            mip.state.add_directly_installed('mip-org/core/testpkg');

            testCase.verifyTrue(ismember('gh/mip-org/core/testpkg', ...
                mip.state.get_directly_installed()));

            mip.state.remove_directly_installed('mip-org/core/testpkg');
            testCase.verifyFalse(ismember('gh/mip-org/core/testpkg', ...
                mip.state.get_directly_installed()));
        end

        function testUnloadBeforeUninstall(testCase)
            % Simulate what uninstall does: unload first, then remove
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/testpkg'));

            mip.unload('mip-org/core/testpkg');
            testCase.verifyFalse(mip.state.is_loaded('mip-org/core/testpkg'));

            rmdir(pkgDir, 's');
            testCase.verifyFalse(exist(pkgDir, 'dir') > 0);
        end

        function testUninstall_PerPackageOrderInterleaving(testCase)
            % Multi-package uninstall: each package's full lifecycle
            % (Unloaded / Uninstalling / Uninstalled) must appear in
            % argument order before the next package starts, not batched
            % across phases.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            mip.state.add_directly_installed('mip-org/core/alpha');
            mip.state.add_directly_installed('mip-org/core/beta');
            mip.load('mip-org/core/alpha');
            mip.load('mip-org/core/beta');

            output = evalc('mip.uninstall(''mip-org/core/alpha'', ''mip-org/core/beta'')');

            posAlphaUnloaded    = strfind(output, 'Unloaded package "mip-org/core/alpha"');
            posAlphaUninstalled = strfind(output, 'Uninstalled package "mip-org/core/alpha"');
            posBetaUnloaded     = strfind(output, 'Unloaded package "mip-org/core/beta"');
            posBetaUninstalled  = strfind(output, 'Uninstalled package "mip-org/core/beta"');

            testCase.verifyNotEmpty(posAlphaUnloaded);
            testCase.verifyNotEmpty(posAlphaUninstalled);
            testCase.verifyNotEmpty(posBetaUnloaded);
            testCase.verifyNotEmpty(posBetaUninstalled);

            % Alpha's full lifecycle must complete before beta's begins
            testCase.verifyTrue(posAlphaUnloaded(1)    < posAlphaUninstalled(1));
            testCase.verifyTrue(posAlphaUninstalled(1) < posBetaUnloaded(1), ...
                'beta''s unload must come AFTER alpha''s uninstall completes');
            testCase.verifyTrue(posBetaUnloaded(1)     < posBetaUninstalled(1));
        end

        function testPackageNoLongerDiscoverableAfterRemoval(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            fqn = mip.resolve.resolve_bare_name('testpkg');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/testpkg');

            pkgDir = mip.paths.get_package_dir('mip-org/core/testpkg');
            rmdir(pkgDir, 's');

            fqn = mip.resolve.resolve_bare_name('testpkg');
            testCase.verifyEqual(fqn, '');
        end

        function testCleanupEmptyParentDirs(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'testorg', 'testchan', 'testpkg');
            chanDir = fullfile(testCase.TestRoot, 'packages', 'gh', 'testorg', 'testchan');
            orgDir = fullfile(testCase.TestRoot, 'packages', 'gh', 'testorg');

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
            allMatches = mip.resolve.find_all_installed_by_name('duppkg');
            testCase.verifyEqual(length(allMatches), 2, ...
                'Should find two installed packages with same bare name');
            testCase.verifyTrue(ismember('gh/mip-org/core/duppkg', allMatches));
            testCase.verifyTrue(ismember('gh/other-org/extras/duppkg', allMatches));
        end

        function testUninstallBareNameUnique_ResolvesNormally(testCase)
            % When bare name matches exactly one installed package, resolve it
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'uniqpkg');

            allMatches = mip.resolve.find_all_installed_by_name('uniqpkg');
            testCase.verifyEqual(length(allMatches), 1);
            testCase.verifyEqual(allMatches{1}, 'gh/mip-org/core/uniqpkg');
        end

        function testUninstallFQN_BypassesAmbiguityCheck(testCase)
            % Using FQN should work even when bare name is ambiguous
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'duppkg');
            createTestPackage(testCase.TestRoot, 'other-org', 'extras', 'duppkg');

            % FQN parsing should identify it as FQN and skip bare name resolution
            result = mip.parse.parse_package_arg('other-org/extras/duppkg');
            testCase.verifyTrue(result.is_fqn);
        end

        %% --- prune_unused_packages utility (issue #100) ---

        function testPruneRemovesOrphans(testCase)
            % A package that is on disk but not in directly_installed.txt
            % and not a dep of anything directly installed should be pruned.
            orphanDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'orphan');

            mip.state.prune_unused_packages();

            testCase.verifyFalse(exist(orphanDir, 'dir') > 0, ...
                'Orphan should be pruned');
        end

        function testPrunePreservesDirectlyInstalled(testCase)
            % A directly-installed package should never be pruned, even
            % if nothing else references it.
            keepDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'keep');
            mip.state.add_directly_installed('mip-org/core/keep');

            mip.state.prune_unused_packages();

            testCase.verifyTrue(exist(keepDir, 'dir') > 0, ...
                'Directly-installed package should be preserved');
        end

        function testPrunePreservesTransitiveDeps(testCase)
            % A package reachable from a directly-installed package via
            % its mip.json dependencies should be preserved.
            parentDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'parent', ...
                'dependencies', {'child'});
            childDir  = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'child');
            mip.state.add_directly_installed('mip-org/core/parent');

            mip.state.prune_unused_packages();

            testCase.verifyTrue(exist(parentDir, 'dir') > 0, ...
                'Directly-installed parent should be preserved');
            testCase.verifyTrue(exist(childDir, 'dir') > 0, ...
                'Bare-name dep of directly-installed parent should be preserved');
        end

        function testPruneRemovesOrphanAlongsideDirectlyInstalled(testCase)
            % Mixed state: a directly-installed package coexists with an
            % orphan. Only the orphan is removed.
            keepDir   = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'keep');
            orphanDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'orphan');
            mip.state.add_directly_installed('mip-org/core/keep');

            mip.state.prune_unused_packages();

            testCase.verifyTrue(exist(keepDir, 'dir') > 0);
            testCase.verifyFalse(exist(orphanDir, 'dir') > 0);
        end

        function testPruneNeverRemovesMipItself(testCase)
            % mip-org/core/mip is the package manager and must be exempt
            % from pruning even when it isn't in directly_installed.txt.
            mipDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');

            mip.state.prune_unused_packages();

            testCase.verifyTrue(exist(mipDir, 'dir') > 0, ...
                'mip-org/core/mip must never be pruned');
        end

    end
end
