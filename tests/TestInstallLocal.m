classdef TestInstallLocal < matlab.unittest.TestCase
%TESTINSTALLLOCAL   Tests for mip.install with local directories (editable and copy).

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
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package directory should be created');
        end

        function testEditableInstall_CreatesMipJson(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(fullfile(pkgDir, 'mip.json'), 'file') > 0);

            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.name, 'mypkg');
            testCase.verifyTrue(info.editable);
        end

        function testEditableInstall_RecordsPathsInMipJson(testCase)
            % Installs carry the paths list inside mip.json.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'paths'), ...
                'Editable install should record "paths" in mip.json');
        end

        function testEditableInstall_MarkedAsDirectlyInstalled(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgs = mip.state.get_directly_installed();
            testCase.verifyTrue(ismember('local/mypkg', pkgs));
        end

        function testEditableInstall_LoadResolvesToSourceDir(testCase)
            % Editable installs resolve "paths" against source_path (the
            % original source dir), so mip.load adds that directory to the
            % MATLAB path.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(info.editable);
            testCase.verifyEqual(info.source_path, srcDir);

            % After loading, the source dir itself should be on the MATLAB path.
            mip.load('mypkg');
            testCase.addTeardown(@() mip.unload('mypkg'));
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));
        end

        function testEditableInstall_MipJsonHasSourcePath(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'source_path'));
            testCase.verifyTrue(contains(info.source_path, testCase.SourceDir));
        end

        function testEditableInstall_UsesLocalLocalChannel(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgs = mip.state.list_installed_packages();
            testCase.verifyTrue(ismember('local/mypkg', pkgs));
        end

        function testEditableInstall_AlreadyInstalled(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);
            % Second install should print message but not error
            mip.install('-e', srcDir);
        end

        function testCopyInstall_CreatesPackageDir(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);
        end

        function testCopyInstall_CreatesMipJson(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.name, 'mypkg');
        end

        function testCopyInstall_LoadResolvesToInstalledSourceDir(testCase)
            % Copy installs resolve "paths" against pkgDir/<name>/ (the
            % installed source subdir), independent of the original
            % source location.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'paths'), ...
                'Copy install should record "paths" in mip.json');
            testCase.verifyFalse(isfield(info, 'editable') && info.editable);

            expectedSrcDir = fullfile(pkgDir, 'mypkg');
            mip.load('mypkg');
            testCase.addTeardown(@() mip.unload('mypkg'));
            testCase.verifyTrue(ismember(expectedSrcDir, strsplit(path, pathsep)));
            testCase.verifyFalse(ismember(srcDir, strsplit(path, pathsep)), ...
                'Copy install should not put the original source dir on the path');
        end

        function testInstallLocal_WithDependency(testCase)
            % Create the dependency as an installed package first
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');

            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'depA'});
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);
        end

        function testInstallLocal_MissingDependencyErrors(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'dependencies', {'nonexistent_dep'});
            testCase.verifyError(@() mip.install('-e', srcDir), ...
                'mip:dependencyNotFound');
        end

        function testInstallLocal_ShowsLoadHintWithBareName(testCase)
            % When no other package shares the name, hint uses bare name
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            output = evalc('mip.install(''-e'', srcDir)');
            testCase.verifyTrue(contains(output, 'mip load mypkg'), ...
                'Should show bare name in load hint when name is unique');
            testCase.verifyFalse(contains(output, 'mip load local/mypkg'), ...
                'Should not show FQN when name is unique');
        end

        function testInstallLocal_ShowsLoadHintWithFQN(testCase)
            % When another package with the same name exists, hint uses FQN
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mypkg');
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            output = evalc('mip.install(''-e'', srcDir)');
            testCase.verifyTrue(contains(output, 'mip load local/mypkg'), ...
                'Should show FQN in load hint when name is not unique');
        end

        function testInstallLocal_HintSectionPresent(testCase)
            % Verify the hint section header is present
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            output = evalc('mip.install(''-e'', srcDir)');
            testCase.verifyTrue(contains(output, 'To use this package, run:'), ...
                'Should show hint section header after install');
        end

        function testCopyInstall_StoresSourcePath(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install(srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'source_path'), ...
                'Non-editable local install should store source_path in mip.json');
            testCase.verifyTrue(contains(info.source_path, testCase.SourceDir), ...
                'source_path should point to original source directory');
        end

        function testEditableInstall_StoresSourcePath(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.install('-e', srcDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'source_path'));
            testCase.verifyTrue(contains(info.source_path, testCase.SourceDir));
        end

        %% --- Path-vs-name dispatch (issue #107) ---

        function testInstall_TwoPartSpecRaisesInvalidPackageSpec(testCase)
            % "foo/bar" is neither a bare name nor a FQN; it should be
            % rejected with a parse error before any channel fetch.
            testCase.verifyError(@() mip.install('foo/bar'), ...
                'mip:install:invalidPackageSpec');
        end

        function testInstall_FourPartSpecRaisesInvalidPackageSpec(testCase)
            testCase.verifyError(@() mip.install('a/b/c/d'), ...
                'mip:install:invalidPackageSpec');
        end

        function testInstall_TwoPartSpecHintsAtSlashPrefix(testCase)
            % The error message for an invalid spec should hint at './foo/bar'
            % so the user knows how to install it as a local package.
            try
                mip.install('foo/bar');
                testCase.verifyFail('Expected mip.install to error');
            catch ME
                testCase.verifyEqual(ME.identifier, 'mip:install:invalidPackageSpec');
                testCase.verifyTrue(contains(ME.message, './foo/bar'), ...
                    'Error message should hint at ./foo/bar');
            end
        end

        function testInstall_RelativeDotPathInstallsLocally(testCase)
            % A path starting with './' should be treated as a local install.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            origCwd = pwd;
            cleanupCwd = onCleanup(@() cd(origCwd));
            cd(testCase.SourceDir);

            mip.install('./mypkg');

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                './mypkg should install locally');
            testCase.verifyTrue(exist(srcDir, 'dir') > 0);
        end

        function testInstall_EditableRequiresLocalForBareName(testCase)
            % `-e bare_name` should error since bare names are not local.
            testCase.verifyError(@() mip.install('-e', 'somepkg'), ...
                'mip:install:editableRequiresLocal');
        end

        function testInstall_WindowsDrivePathBackslashTreatedAsLocal(testCase)
            % A Windows drive-letter path like 'C:\nonexistent' must be
            % categorized as a local path, not a bare name. On non-Windows
            % platforms it will fail with notADirectory rather than be
            % parsed as a package spec.
            testCase.verifyError(@() mip.install('C:\nonexistent_mip_pkg'), ...
                'mip:install:notADirectory');
        end

        function testInstall_WindowsDrivePathForwardSlashTreatedAsLocal(testCase)
            % Forward-slash form of a Windows drive path is also accepted.
            % Without the drive-letter rule, 'C:/foo/bar' would have 3
            % slash-separated parts and look like a (malformed) FQN.
            testCase.verifyError(@() mip.install('D:/nonexistent/mip_pkg'), ...
                'mip:install:notADirectory');
        end

        function testInstall_WindowsDrivePathRespectsEditableFlag(testCase)
            % `-e C:\path` should be accepted as an editable local install
            % attempt (and fail at the directory check, not the
            % editableRequiresLocal check).
            testCase.verifyError(@() mip.install('-e', 'C:\nonexistent_mip_pkg'), ...
                'mip:install:notADirectory');
        end

        %% --- @ in local paths (issue #107) ---
        % When a local-path prefix (~, ., /) is present, '@' is a literal
        % path character, not a version separator.

        function testInstall_DotSlashAtDirTreatedAsLocal(testCase)
            % './@foo' should be categorized as a local path, not parsed
            % as a bare name with '@' version syntax.
            testCase.verifyError(@() mip.install('./@nonexistent_mip_pkg'), ...
                'mip:install:notADirectory');
        end

        function testInstall_DotSlashPathWithAtTreatedAsLocal(testCase)
            % './pkg@1.0' should be categorized as a local path, not
            % split on '@' to extract a version.
            testCase.verifyError(@() mip.install('./pkg@1.0'), ...
                'mip:install:notADirectory');
        end

        function testInstall_AbsolutePathWithAtTreatedAsLocal(testCase)
            % An absolute path containing '@' is still a local path.
            testCase.verifyError(@() mip.install('/nonexistent/@mip_pkg'), ...
                'mip:install:notADirectory');
        end

        function testInstall_LocalDirWithAtInstallsSuccessfully(testCase)
            % A local directory whose name contains '@' should install
            % when prefixed with './'. The '@' is part of the path, not
            % a version separator.
            atDir = fullfile(testCase.SourceDir, 'pkg@dev');
            mkdir(atDir);
            fid = fopen(fullfile(atDir, 'mip.yaml'), 'w');
            fprintf(fid, 'name: mypkg\nversion: "1.0.0"\n');
            fprintf(fid, 'description: "Test"\nlicense: MIT\n');
            fprintf(fid, 'dependencies: []\npaths:\n  - path: "."\n');
            fprintf(fid, 'builds:\n  - architectures: [any]\n');
            fclose(fid);
            fid = fopen(fullfile(atDir, 'mypkg.m'), 'w');
            fprintf(fid, 'function r = mypkg(), r = 1; end\n');
            fclose(fid);

            origCwd = pwd;
            cleanupCwd = onCleanup(@() cd(origCwd));
            cd(testCase.SourceDir);

            mip.install('./pkg@dev');

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package from @-containing directory should be installed');
        end

        function testInstall_EditableLocalDirWithAt(testCase)
            % Editable install from a directory with '@' in the name.
            atDir = fullfile(testCase.SourceDir, '@MyClass');
            mkdir(atDir);
            fid = fopen(fullfile(atDir, 'mip.yaml'), 'w');
            fprintf(fid, 'name: myclass\nversion: "1.0.0"\n');
            fprintf(fid, 'description: "Test"\nlicense: MIT\n');
            fprintf(fid, 'dependencies: []\npaths:\n  - path: "."\n');
            fprintf(fid, 'builds:\n  - architectures: [any]\n');
            fclose(fid);
            fid = fopen(fullfile(atDir, 'myclass.m'), 'w');
            fprintf(fid, 'function r = myclass(), r = 1; end\n');
            fclose(fid);

            mip.install('-e', atDir);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'myclass');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Editable install from @-directory should succeed');
            info = mip.config.read_package_json(pkgDir);
            testCase.verifyTrue(info.editable);
            testCase.verifyTrue(contains(info.source_path, '@MyClass'));
        end

    end
end
