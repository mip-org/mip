classdef TestNameVariants < matlab.unittest.TestCase
%TESTNAMEVARIANTS   End-to-end tests that user-facing commands accept
%   case- and dash/underscore-variant package names equivalently.
%
% These tests are the safety net for the canonicalize-at-boundary design:
% if a future change re-introduces a case-sensitive comparison anywhere
% on a command's path, one of these tests should fail.
%
% Convention used here: the test package is installed on disk as
% 'My-Pkg', and each test invokes a command using one of several
% equivalent forms ('my_pkg', 'MY_PKG', 'mip-org/core/My-Pkg', etc).

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

    methods (Access = private)
        function makePkg(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'My-Pkg');
        end

        function fqn = canonicalFqn(~)
            fqn = 'mip-org/core/My-Pkg';
        end
    end

    methods (Test)

        %% Variants accepted by resolve_bare_name (and consumers)

        function testResolveBareName_CaseVariant(testCase)
            testCase.makePkg();
            testCase.verifyEqual(mip.resolve.resolve_bare_name('MYPKG'), '');
            % MYPKG (no separator) does NOT match My-Pkg (with dash) — only
            % case and `-`/`_` are interchangeable, not separator presence.
            testCase.verifyEqual(mip.resolve.resolve_bare_name('my_pkg'), testCase.canonicalFqn());
            testCase.verifyEqual(mip.resolve.resolve_bare_name('MY-PKG'), testCase.canonicalFqn());
            testCase.verifyEqual(mip.resolve.resolve_bare_name('MY_PKG'), testCase.canonicalFqn());
        end

        function testFindAllInstalledByName_Variant(testCase)
            testCase.makePkg();
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'my_pkg');
            matches = mip.resolve.find_all_installed_by_name('MY-PKG');
            testCase.verifyEqual(sort(matches), ...
                sort({'mip-org/core/My-Pkg', 'mylab/custom/my_pkg'}));
        end

        function testGetPackageDir_VariantReturnsOnDiskPath(testCase)
            testCase.makePkg();
            expected = fullfile(testCase.TestRoot, 'packages', 'mip-org', 'core', 'My-Pkg');
            testCase.verifyEqual( ...
                mip.paths.get_package_dir('mip-org', 'core', 'my_pkg'), expected);
            testCase.verifyEqual( ...
                mip.paths.get_package_dir('mip-org', 'core', 'MY-PKG'), expected);
        end

        function testGetPackageDir_NotInstalledFallsBack(testCase)
            % When no install exists, get_package_dir returns the path with
            % the as-typed name (used by install for new packages).
            expected = fullfile(testCase.TestRoot, 'packages', 'mip-org', 'core', 'NewPkg');
            testCase.verifyEqual( ...
                mip.paths.get_package_dir('mip-org', 'core', 'NewPkg'), expected);
        end

        function testResolveToInstalled_FqnVariantReturnsCanonical(testCase)
            testCase.makePkg();
            r = mip.resolve.resolve_to_installed('mip-org/core/my_pkg');
            testCase.verifyEqual(r.fqn, testCase.canonicalFqn());
            testCase.verifyEqual(r.name, 'My-Pkg');
        end

        function testResolveToInstalled_BareVariantReturnsCanonical(testCase)
            testCase.makePkg();
            r = mip.resolve.resolve_to_installed('MYPKG');
            % bare 'MYPKG' (no separator) is not equivalent to 'My-Pkg'
            testCase.verifyEqual(r, []);
            r = mip.resolve.resolve_to_installed('my_pkg');
            testCase.verifyEqual(r.fqn, testCase.canonicalFqn());
        end

        %% load

        function testLoad_BareVariant(testCase)
            testCase.makePkg();
            mip.load('my_pkg');
            testCase.verifyTrue(mip.state.is_loaded(testCase.canonicalFqn()));
        end

        function testLoad_FqnVariant(testCase)
            testCase.makePkg();
            mip.load('mip-org/core/MY_PKG');
            testCase.verifyTrue(mip.state.is_loaded(testCase.canonicalFqn()));
        end

        function testLoad_AlreadyLoadedDetectedAcrossVariants(testCase)
            testCase.makePkg();
            mip.load('My-Pkg');
            % loading again with a variant should be a no-op, not a re-load
            mip.load('mip-org/core/MY_PKG');
            loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
            % Should appear exactly once and as the canonical form
            count = sum(strcmp(loaded, testCase.canonicalFqn()));
            testCase.verifyEqual(count, 1);
        end

        function testLoad_StickyFlagWithVariantInput(testCase)
            testCase.makePkg();
            mip.load('my_pkg', '--sticky');
            % --sticky on a variant input still marks the canonical FQN
            % as sticky in storage.
            testCase.verifyTrue(mip.state.is_sticky(testCase.canonicalFqn()));
            sticky = mip.state.key_value_get('MIP_STICKY_PACKAGES');
            testCase.verifyTrue(any(strcmp(sticky, testCase.canonicalFqn())));
        end

        %% unload

        function testUnload_BareVariant(testCase)
            testCase.makePkg();
            mip.load(testCase.canonicalFqn());
            mip.unload('my_pkg');
            testCase.verifyFalse(mip.state.is_loaded(testCase.canonicalFqn()));
        end

        function testUnload_FqnVariant(testCase)
            testCase.makePkg();
            mip.load(testCase.canonicalFqn());
            mip.unload('mip-org/core/MY_PKG');
            testCase.verifyFalse(mip.state.is_loaded(testCase.canonicalFqn()));
        end

        %% uninstall

        function testUninstall_BareVariant(testCase)
            testCase.makePkg();
            mip.state.add_directly_installed(testCase.canonicalFqn());
            mip.uninstall('my_pkg');
            testCase.verifyFalse(mip.state.is_installed(testCase.canonicalFqn()));
            testCase.verifyEmpty(mip.state.get_directly_installed());
        end

        function testUninstall_FqnVariant(testCase)
            testCase.makePkg();
            mip.state.add_directly_installed(testCase.canonicalFqn());
            mip.uninstall('mip-org/core/MY_PKG');
            testCase.verifyFalse(mip.state.is_installed(testCase.canonicalFqn()));
            testCase.verifyEmpty(mip.state.get_directly_installed());
        end

        %% state queries

        function testIsInstalled_VariantReturnsTrue(testCase)
            testCase.makePkg();
            testCase.verifyTrue(mip.state.is_installed('mip-org/core/my_pkg'));
            testCase.verifyTrue(mip.state.is_installed('mip-org/core/MY-PKG'));
        end

        function testIsLoaded_AfterVariantLoadUsesCanonicalFqn(testCase)
            % Loading via a variant flows the canonical FQN into state,
            % so subsequent is_loaded queries against the canonical form
            % succeed. (Callers query with canonical because they get
            % FQNs from resolve_to_installed / resolveToFqn / list_*.)
            testCase.makePkg();
            mip.load('my_pkg');
            testCase.verifyTrue(mip.state.is_loaded(testCase.canonicalFqn()));
        end

        %% directly_installed bookkeeping

        function testDirectlyInstalled_AddedAsCanonical(testCase)
            testCase.makePkg();
            % Even if a (hypothetical) caller hands a non-canonical FQN to
            % the install side, adding always uses the canonical form via
            % the canonicalize-at-boundary in install.m. Here we simulate
            % by adding a canonical entry and confirm dedup is exact.
            mip.state.add_directly_installed(testCase.canonicalFqn());
            mip.state.add_directly_installed(testCase.canonicalFqn());
            testCase.verifyEqual( ...
                mip.state.get_directly_installed(), ...
                {testCase.canonicalFqn()});
        end

    end
end
