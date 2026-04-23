classdef TestInstallPromptInit < matlab.unittest.TestCase
%TESTINSTALLPROMPTINIT   Tests for mip install prompting to auto-init
% missing mip.yaml when installing a local directory.

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
        SourceDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_install_init_test'];
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
            setenv('MIP_CONFIRM', testCase.OrigMipConfirm);
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

        function testNonEditable_AutoInitOnYes(testCase)
            % Directory has no mip.yaml. With MIP_CONFIRM=y, install
            % should auto-generate a mip.yaml and proceed.
            pkgDir = fullfile(testCase.SourceDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'y');
            mip.install(pkgDir);

            % mip.yaml created in source
            testCase.verifyTrue(exist(fullfile(pkgDir, 'mip.yaml'), 'file') > 0);
            % Package installed
            installedDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0);
        end

        function testEditable_AutoInitOnYes(testCase)
            pkgDir = fullfile(testCase.SourceDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'y');
            mip.install('-e', pkgDir);

            testCase.verifyTrue(exist(fullfile(pkgDir, 'mip.yaml'), 'file') > 0);
            installedDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0);

            info = mip.config.read_package_json(installedDir);
            testCase.verifyTrue(info.editable, 'editable flag should be set');
        end

        function testNonEditable_AbortsOnNo(testCase)
            pkgDir = fullfile(testCase.SourceDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'n');
            testCase.verifyError(@() mip.install(pkgDir), ...
                'mip:install:abortedNoMipYaml');

            % No mip.yaml created, no install
            testCase.verifyFalse(exist(fullfile(pkgDir, 'mip.yaml'), 'file') > 0);
            installedDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyFalse(exist(installedDir, 'dir') > 0);
        end

        function testEditable_AbortsOnNo(testCase)
            pkgDir = fullfile(testCase.SourceDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'n');
            testCase.verifyError(@() mip.install('-e', pkgDir), ...
                'mip:install:abortedNoMipYaml');

            testCase.verifyFalse(exist(fullfile(pkgDir, 'mip.yaml'), 'file') > 0);
        end

        function testEmptyConfirmAborts(testCase)
            % Anything other than y/yes is treated as "no". Empty string
            % (the default if user just hits enter) declines.
            pkgDir = fullfile(testCase.SourceDir, 'mypkg');
            mkdir(pkgDir);

            % With MIP_CONFIRM unset, would normally prompt. We can't
            % easily simulate stdin, so this case is covered by the 'n'
            % path. Skip — but verify that arbitrary non-yes value declines.
            setenv('MIP_CONFIRM', 'empty');
            testCase.verifyError(@() mip.install(pkgDir), ...
                'mip:install:abortedNoMipYaml');
        end

        function testYesAlias(testCase)
            % "yes" (full word) should also confirm.
            pkgDir = fullfile(testCase.SourceDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'yes');
            mip.install(pkgDir);

            installedDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0);
        end

        function testExistingMipYamlNoPrompt(testCase)
            % If mip.yaml already exists, no prompting happens — the
            % install proceeds normally regardless of MIP_CONFIRM.
            pkgDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');

            setenv('MIP_CONFIRM', 'n');  % would abort if prompted
            mip.install(pkgDir);

            installedDir = fullfile(testCase.TestRoot, 'packages', 'local', 'mypkg');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0);
        end

        function testGeneratedYamlUsesDirBasename(testCase)
            pkgDir = fullfile(testCase.SourceDir, 'somepkgname');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'y');
            mip.install(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'somepkgname');

            installedDir = fullfile(testCase.TestRoot, 'packages', 'local', 'somepkgname');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0);
        end

        function testAbortLeavesNoPartialState(testCase)
            % After aborting, the source dir should not have been touched
            % at all (no mip.yaml, no test_*.m).
            pkgDir = fullfile(testCase.SourceDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'n');
            try
                mip.install(pkgDir);
            catch
            end

            entries = dir(pkgDir);
            names = {entries.name};
            testCase.verifyFalse(any(strcmp(names, 'mip.yaml')));
            testCase.verifyFalse(any(strcmp(names, 'test_mypkg.m')));
        end

        function testMultiplePathsAbortStopsAtFirstNo(testCase)
            % Two local paths, neither has mip.yaml. User says no on the
            % first one. The whole install aborts; the second is not
            % processed.
            pkgA = fullfile(testCase.SourceDir, 'pkgA');
            pkgB = fullfile(testCase.SourceDir, 'pkgB');
            mkdir(pkgA);
            mkdir(pkgB);
            fid = fopen(fullfile(pkgA, 'a.m'), 'w');
            fprintf(fid, 'function y = a(x); y = x; end\n');
            fclose(fid);
            fid = fopen(fullfile(pkgB, 'b.m'), 'w');
            fprintf(fid, 'function y = b(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'n');
            testCase.verifyError(@() mip.install(pkgA, pkgB), ...
                'mip:install:abortedNoMipYaml');

            testCase.verifyFalse(exist(fullfile(pkgA, 'mip.yaml'), 'file') > 0);
            testCase.verifyFalse(exist(fullfile(pkgB, 'mip.yaml'), 'file') > 0);
        end

        function testMultiplePathsBothInitialized(testCase)
            % Two local paths, neither has mip.yaml. User says yes (via
            % MIP_CONFIRM); both are init'd and installed. Directory names
            % are canonical (lowercase) so init accepts them.
            pkgA = fullfile(testCase.SourceDir, 'pkga');
            pkgB = fullfile(testCase.SourceDir, 'pkgb');
            mkdir(pkgA);
            mkdir(pkgB);
            fid = fopen(fullfile(pkgA, 'a.m'), 'w');
            fprintf(fid, 'function y = a(x); y = x; end\n');
            fclose(fid);
            fid = fopen(fullfile(pkgB, 'b.m'), 'w');
            fprintf(fid, 'function y = b(x); y = x; end\n');
            fclose(fid);

            setenv('MIP_CONFIRM', 'y');
            mip.install(pkgA, pkgB);

            testCase.verifyTrue(exist(fullfile(pkgA, 'mip.yaml'), 'file') > 0);
            testCase.verifyTrue(exist(fullfile(pkgB, 'mip.yaml'), 'file') > 0);

            installedA = fullfile(testCase.TestRoot, 'packages', 'local', 'pkga');
            installedB = fullfile(testCase.TestRoot, 'packages', 'local', 'pkgb');
            testCase.verifyTrue(exist(installedA, 'dir') > 0);
            testCase.verifyTrue(exist(installedB, 'dir') > 0);
        end

    end
end
