classdef TestPackageDiscovery < matlab.unittest.TestCase
%TESTPACKAGEDISCOVERY   Tests for resolve_bare_name, list_installed_packages,
%   and directly_installed file operations.

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

        %% resolve_bare_name tests

        function testResolveBareName_NotFound(testCase)
            fqn = mip.resolve.resolve_bare_name('nonexistent');
            testCase.verifyEqual(fqn, '');
        end

        function testResolveBareName_SingleMatch(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'chebfun');
            fqn = mip.resolve.resolve_bare_name('chebfun');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/chebfun');
        end

        function testResolveBareName_PrefersCoreChannel(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'testpkg');
            fqn = mip.resolve.resolve_bare_name('testpkg');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/testpkg');
        end

        function testResolveBareName_FallsBackToAlphabetical(testCase)
            createTestPackage(testCase.TestRoot, 'alab', 'chan1', 'testpkg');
            createTestPackage(testCase.TestRoot, 'zlab', 'chan2', 'testpkg');
            fqn = mip.resolve.resolve_bare_name('testpkg');
            testCase.verifyEqual(fqn, 'gh/alab/chan1/testpkg');
        end

        function testResolveBareName_CustomChannelOnly(testCase)
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'mypkg');
            fqn = mip.resolve.resolve_bare_name('mypkg');
            testCase.verifyEqual(fqn, 'gh/mylab/custom/mypkg');
        end

        function testResolveBareName_LocalInstall(testCase)
            createTestPackage(testCase.TestRoot, '', '', 'devpkg', 'type', 'local');
            fqn = mip.resolve.resolve_bare_name('devpkg');
            testCase.verifyEqual(fqn, 'local/devpkg');
        end

        %% resolve_dependency tests

        function testResolveDependency_FqnPassthrough(testCase)
            fqn = mip.resolve.resolve_dependency('gh/mip-org/core/chebfun');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/chebfun');
        end

        function testResolveDependency_BareNameResolvesToCore(testCase)
            fqn = mip.resolve.resolve_dependency('chebfun');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/chebfun');
        end

        function testResolveDependency_BareNameIgnoresSameChannel(testCase)
            % Even when a package with the same name exists on a non-core
            % channel, bare-name deps always resolve to gh/mip-org/core.
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'somepkg');
            fqn = mip.resolve.resolve_dependency('somepkg');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/somepkg');
        end

        function testResolveDependency_NonCoreFqnPreserved(testCase)
            fqn = mip.resolve.resolve_dependency('mylab/custom/somepkg');
            testCase.verifyEqual(fqn, 'gh/mylab/custom/somepkg');
        end

        %% list_installed_packages tests

        function testListInstalled_EmptyDir(testCase)
            pkgs = mip.state.list_installed_packages();
            testCase.verifyEqual(pkgs, {});
        end

        function testListInstalled_SinglePackage(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'chebfun');
            pkgs = mip.state.list_installed_packages();
            testCase.verifyEqual(pkgs, {'gh/mip-org/core/chebfun'});
        end

        function testListInstalled_MultiplePackages(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'gamma');
            pkgs = mip.state.list_installed_packages();
            testCase.verifyEqual(sort(pkgs), ...
                sort({'gh/mip-org/core/alpha', 'gh/mip-org/core/beta', 'gh/mylab/custom/gamma'}));
        end

        function testListInstalled_IsSorted(testCase)
            createTestPackage(testCase.TestRoot, 'zlab', 'chan', 'zpkg');
            createTestPackage(testCase.TestRoot, 'alab', 'chan', 'apkg');
            pkgs = mip.state.list_installed_packages();
            testCase.verifyEqual(pkgs, {'gh/alab/chan/apkg', 'gh/zlab/chan/zpkg'});
        end

        %% directly_installed tests

        function testDirectlyInstalled_EmptyByDefault(testCase)
            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(pkgs, {});
        end

        function testDirectlyInstalled_AddAndGet(testCase)
            mip.state.add_directly_installed('gh/mip-org/core/chebfun');
            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(pkgs, {'gh/mip-org/core/chebfun'});
        end

        function testDirectlyInstalled_AddDuplicate(testCase)
            mip.state.add_directly_installed('gh/mip-org/core/chebfun');
            mip.state.add_directly_installed('gh/mip-org/core/chebfun');
            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(pkgs, {'gh/mip-org/core/chebfun'});
        end

        function testDirectlyInstalled_AddMultiple(testCase)
            mip.state.add_directly_installed('mip-org/core/alpha');
            mip.state.add_directly_installed('mip-org/core/beta');
            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(sort(pkgs), sort({'gh/mip-org/core/alpha', 'gh/mip-org/core/beta'}));
        end

        function testDirectlyInstalled_Remove(testCase)
            mip.state.add_directly_installed('mip-org/core/alpha');
            mip.state.add_directly_installed('mip-org/core/beta');
            mip.state.remove_directly_installed('mip-org/core/alpha');
            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(pkgs, {'gh/mip-org/core/beta'});
        end

        function testDirectlyInstalled_RemoveNonExistent(testCase)
            mip.state.add_directly_installed('mip-org/core/alpha');
            mip.state.remove_directly_installed('mip-org/core/nonexistent');
            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(pkgs, {'gh/mip-org/core/alpha'});
        end

        function testDirectlyInstalled_SetOverwrites(testCase)
            mip.state.add_directly_installed('mip-org/core/old');
            mip.state.set_directly_installed({'mip-org/core/new1', 'mip-org/core/new2'});
            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(sort(pkgs), sort({'mip-org/core/new1', 'mip-org/core/new2'}));
        end

        function testDirectlyInstalled_StaleTmpReplaced(testCase)
            % A leftover directly_installed.txt.tmp (e.g. from a prior crash)
            % must be replaced, and the final file must contain only the
            % new entries.
            packagesDir = mip.paths.get_packages_dir();
            if ~exist(packagesDir, 'dir')
                mkdir(packagesDir);
            end
            tmpPath = fullfile(packagesDir, 'directly_installed.txt.tmp');
            fid = fopen(tmpPath, 'w');
            fprintf(fid, 'mip-org/core/garbage\n');
            fclose(fid);

            mip.state.set_directly_installed({'mip-org/core/alpha', 'mip-org/core/beta'});

            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(sort(pkgs), sort({'mip-org/core/alpha', 'mip-org/core/beta'}));
            testCase.verifyFalse(exist(tmpPath, 'file') > 0, ...
                'directly_installed.txt.tmp should not exist after a successful write');
        end

        function testDirectlyInstalled_PreservedOnWriteFailure(testCase)
            % If writing to the tmp file fails, the original
            % directly_installed.txt must remain intact — this is the
            % invariant the atomic write protects.
            mip.state.set_directly_installed({'mip-org/core/keep1', 'mip-org/core/keep2'});

            % Force fopen(tmpPath, 'w') to fail by pre-creating the tmp
            % path as a directory.
            packagesDir = mip.paths.get_packages_dir();
            tmpPath = fullfile(packagesDir, 'directly_installed.txt.tmp');
            mkdir(tmpPath);

            testCase.verifyError( ...
                @() mip.state.set_directly_installed({'mip-org/core/nope'}), ...
                'mip:fileError');

            pkgs = mip.state.get_directly_installed();
            testCase.verifyEqual(sort(pkgs), ...
                sort({'mip-org/core/keep1', 'mip-org/core/keep2'}));
        end

        %% get_package_dir tests

        function testGetPackageDir(testCase)
            pkgDir = mip.paths.get_package_dir('gh/mip-org/core/chebfun');
            expected = fullfile(testCase.TestRoot, 'packages', 'gh', 'mip-org', 'core', 'chebfun');
            testCase.verifyEqual(pkgDir, expected);
        end

        %% is_loaded / is_sticky / is_directly_loaded tests

        function testIsLoaded_False(testCase)
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/chebfun'));
        end

        function testIsLoaded_True(testCase)
            mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/chebfun');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/chebfun'));
        end

        function testIsSticky_False(testCase)
            testCase.verifyFalse(mip.state.is_sticky('gh/mip-org/core/chebfun'));
        end

        function testIsSticky_True(testCase)
            mip.state.key_value_append('MIP_STICKY_PACKAGES', 'gh/mip-org/core/chebfun');
            testCase.verifyTrue(mip.state.is_sticky('gh/mip-org/core/chebfun'));
        end

        function testIsDirectlyLoaded_False(testCase)
            testCase.verifyFalse(mip.state.is_directly_loaded('gh/mip-org/core/chebfun'));
        end

        function testIsDirectlyLoaded_True(testCase)
            mip.state.key_value_append('MIP_DIRECTLY_LOADED_PACKAGES', 'gh/mip-org/core/chebfun');
            testCase.verifyTrue(mip.state.is_directly_loaded('gh/mip-org/core/chebfun'));
        end

        %% read_package_json tests

        function testReadPackageJson(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg', ...
                'version', '2.0.0');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.name, 'testpkg');
            testCase.verifyEqual(info.version, '2.0.0');
        end

        function testReadPackageJson_MissingFile(testCase)
            emptyDir = fullfile(testCase.TestRoot, 'empty_pkg');
            mkdir(emptyDir);
            testCase.verifyError(@() mip.config.read_package_json(emptyDir), ...
                'mip:mipJsonNotFound');
        end

    end
end
