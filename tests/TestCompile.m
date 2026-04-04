classdef TestCompile < matlab.unittest.TestCase
%TESTCOMPILE   Tests for editable install compilation and mip compile.
%
%   Tests:
%     - Editable install runs compile by default
%     - --no-compile skips compilation
%     - compile_script stored in mip.json for editable installs
%     - mip compile runs the compile script
%     - mip compile errors on missing package / no compile script
%     - --no-compile errors without --editable

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_compile_test'];
            testCase.SourceDir = [tempname '_mip_compile_src'];
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

        %% --- Editable install compilation ---

        function testEditableInstall_CompilesByDefault(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            mip.utils.install_local(srcDir, true);

            % The compile script creates a .compiled marker file
            testCase.verifyTrue(isfile(fullfile(srcDir, '.compiled')), ...
                'Editable install should compile by default');
        end

        function testEditableInstall_NoCompileSkipsCompilation(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            mip.utils.install_local(srcDir, true, true);

            testCase.verifyFalse(isfile(fullfile(srcDir, '.compiled')), ...
                'Editable install with --no-compile should skip compilation');
        end

        function testEditableInstall_NoCompileScriptSkipsQuietly(testCase)
            % Package without a compile_script should install fine
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            testCase.verifyTrue(exist(pkgDir, 'dir') > 0);
        end

        function testEditableInstall_StoresCompileScript(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            mip.utils.install_local(srcDir, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'compile_script'), ...
                'mip.json should store compile_script');
            testCase.verifyEqual(info.compile_script, 'do_compile.m');
        end

        function testEditableInstall_NoCompileStillStoresScript(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            mip.utils.install_local(srcDir, true, true);

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            info = mip.utils.read_package_json(pkgDir);
            testCase.verifyTrue(isfield(info, 'compile_script'), ...
                'mip.json should store compile_script even with --no-compile');
        end

        function testEditableInstall_PrintsCompileHint(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            output = evalc('mip.utils.install_local(srcDir, true)');

            testCase.verifyTrue(contains(output, 'mip compile'), ...
                'Should print mip compile hint after editable install with compile script');
        end

        function testEditableInstall_NoCompilePrintsHint(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            output = evalc('mip.utils.install_local(srcDir, true, true)');

            testCase.verifyTrue(contains(output, 'mip compile'), ...
                'Should print mip compile hint when --no-compile skips compilation');
        end

        %% --- mip compile command ---

        function testCompile_RunsCompileScript(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            mip.utils.install_local(srcDir, true, true);  % --no-compile

            % Verify not yet compiled
            testCase.verifyFalse(isfile(fullfile(srcDir, '.compiled')));

            % Now run mip compile
            mip.compile('mypkg');

            testCase.verifyTrue(isfile(fullfile(srcDir, '.compiled')), ...
                'mip compile should run the compile script');
        end

        function testCompile_FQNWorks(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            mip.utils.install_local(srcDir, true, true);

            mip.compile('local/local/mypkg');

            testCase.verifyTrue(isfile(fullfile(srcDir, '.compiled')));
        end

        function testCompile_NotInstalledErrors(testCase)
            testCase.verifyError(@() mip.compile('nonexistent'), ...
                'mip:compile:notInstalled');
        end

        function testCompile_NoCompileScriptErrors(testCase)
            % Install a package without a compile script
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.utils.install_local(srcDir, true);

            testCase.verifyError(@() mip.compile('mypkg'), ...
                'mip:compile:noCompileScript');
        end

        %% --- mip compile on non-editable local install ---

        function testCompile_NonEditableCompilesInPkgDir(testCase)
            % mip compile on a non-editable local install should compile
            % in the installed package directory, not the source directory.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            mip.utils.install_local(srcDir, false);

            % Source lives under pkgDir/mypkg/ for non-editable installs
            pkgDir = fullfile(testCase.TestRoot, 'packages', 'local', 'local', 'mypkg');
            pkgSubdir = fullfile(pkgDir, 'mypkg');

            % prepare_package compiled during install; remove the marker
            delete(fullfile(pkgSubdir, '.compiled'));
            testCase.assertFalse(isfile(fullfile(pkgSubdir, '.compiled')));
            testCase.assertFalse(isfile(fullfile(srcDir, '.compiled')));

            % Run mip compile — should compile in pkgSubdir, not srcDir
            mip.compile('mypkg');

            testCase.verifyTrue(isfile(fullfile(pkgSubdir, '.compiled')), ...
                'mip compile should create .compiled in the installed package directory');
            testCase.verifyFalse(isfile(fullfile(srcDir, '.compiled')), ...
                'mip compile should not compile in the source directory');
        end

        %% --- --no-compile flag validation ---

        function testInstall_NoCompileWithoutEditableErrors(testCase)
            testCase.verifyError( ...
                @() mip.install('somepkg', '--no-compile'), ...
                'mip:install:noCompileRequiresEditable');
        end

        function testInstall_NoCompileLocalWithoutEditableErrors(testCase)
            % --no-compile on a local directory without --editable should error
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', ...
                'compile_script', 'do_compile.m');
            testCase.verifyError( ...
                @() mip.install(srcDir, '--no-compile'), ...
                'mip:install:noCompileRequiresEditable');
        end

    end
end
