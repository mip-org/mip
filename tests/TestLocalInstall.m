classdef TestLocalInstall < matlab.unittest.TestCase
%TESTLOCALINSTALL   Tests for mip.utils.install_local (editable and copy).

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
            testCase.SourceDir = [tempname '_mip_src'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            if exist(testCase.SourceDir, 'dir')
                rmdir(testCase.SourceDir, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testEditableInstall_CreatesPackageDir(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package directory should be created');
        end

        function testEditableInstall_CreatesMipJson(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            testCase.verifyTrue(exist(fullfile(pkgDir, 'mip.json'), 'file') > 0);

            info = mip.utils.read_package_json(pkgDir);
            testCase.verifyEqual(info.name, 'mypkg');
            testCase.verifyTrue(info.editable);
        end

        function testEditableInstall_CreatesLoadScript(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            testCase.verifyTrue(exist(fullfile(pkgDir, 'load_package.m'), 'file') > 0);
        end

        function testEditableInstall_CreatesUnloadScript(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            testCase.verifyTrue(exist(fullfile(pkgDir, 'unload_package.m'), 'file') > 0);
        end

        function testEditableInstall_MarkedAsDirectlyInstalled(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgs = mip.utils.get_directly_installed();
            testCase.verifyTrue(ismember('local/local/mypkg', pkgs));
        end

        function testEditableInstall_LoadScriptUsesAbsolutePaths(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            loadScript = fileread(fullfile(pkgDir, 'load_package.m'));
            % Load script should contain absolute path to source
            testCase.verifyTrue(contains(loadScript, srcDir), ...
                'Load script should reference source directory with absolute path');
        end

        function testEditableInstall_MipJsonHasSourcePath(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'source_path'));
            testCase.verifyTrue(contains(info.source_path, testCase.SourceDir));
        end

        function testEditableInstall_UsesLocalLocalChannel(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgs = mip.utils.list_installed_packages();
            testCase.verifyTrue(ismember('local/local/mypkg', pkgs));
        end

        function testEditableInstall_AlreadyInstalled(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);
            % Second install should print message but not error
            mip.utils.install_local(srcDir, true);
        end

        function testCopyInstall_CreatesPackageDir(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);
        end

        function testCopyInstall_CreatesMipJson(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info = mip.utils.read_package_json(pkgDir);
            testCase.verifyEqual(info.name, 'mypkg');
        end

        function testCopyInstall_LoadScriptUsesRelativePaths(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, false);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            loadScript = fileread(fullfile(pkgDir, 'load_package.m'));
            % Copy install load script should use relative paths (pkg_dir)
            testCase.verifyTrue(contains(loadScript, 'pkg_dir'), ...
                'Copy install load script should use relative paths');
        end

        function testInstallLocal_WithDependency(testCase)
            % Create the dependency as an installed package first
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');

            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depA'});
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);
        end

        function testInstallLocal_MissingDependencyErrors(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'nonexistent_dep'});
            testCase.verifyError(@() mip.utils.install_local(srcDir, true), ...
                'mip:dependencyNotFound');
        end

    end
end
