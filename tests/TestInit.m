classdef TestInit < matlab.unittest.TestCase
%TESTINIT   Tests for mip.init.

    properties
        TestDir
    end

    methods (TestMethodSetup)
        function setupTestDir(testCase)
            testCase.TestDir = [tempname '_mip_init_test'];
            mkdir(testCase.TestDir);
        end
    end

    methods (TestMethodTeardown)
        function teardownTestDir(testCase)
            if exist(testCase.TestDir, 'dir')
                rmdir(testCase.TestDir, 's');
            end
        end
    end

    methods (Test)

        function testInit_NoArgsUsesCurrentDir(testCase)
            % With no path argument, init targets the current directory.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            origDir = pwd;
            cleaner = onCleanup(@() cd(origDir));
            cd(pkgDir);

            mip.init();

            testCase.verifyTrue(exist(fullfile(pkgDir, 'mip.yaml'), 'file') > 0);
            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'mypkg');
        end

        function testInit_NonexistentPathErrors(testCase)
            % A path that does not exist is rejected by get_absolute_path.
            testCase.verifyError( ...
                @() mip.init('/nonexistent/path/12345'), ...
                'mip:notAFileOrDirectory');
        end

        function testInit_FileInsteadOfDirErrors(testCase)
            % A path that points to a file (not a directory) is rejected.
            filePath = fullfile(testCase.TestDir, 'a_file.txt');
            fid = fopen(filePath, 'w'); fclose(fid);
            testCase.verifyError(@() mip.init(filePath), 'mip:init:notADirectory');
        end

        function testInit_CreatesMipYaml(testCase)
            % init writes a mip.yaml in the target directory.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            testCase.verifyTrue(exist(fullfile(pkgDir, 'mip.yaml'), 'file') > 0);
        end

        function testInit_DefaultsNameToDirBasename(testCase)
            % When --name is omitted, the package name defaults to the
            % target directory's basename.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'mypkg');
        end

        function testInit_NameOverride(testCase)
            % --name overrides the directory-basename default.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir, '--name', 'overridden');

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'overridden');
        end

        function testInit_RejectsInvalidName(testCase)
            % Names containing disallowed characters (e.g. spaces) are rejected.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', 'bad name'), ...
                'mip:init:invalidName');
        end

        function testInit_RejectsDotDotName(testCase)
            % A name consisting solely of dots is rejected.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', '..'), ...
                'mip:init:invalidName');
        end

        function testInit_RejectsLeadingHyphenName(testCase)
            % Names must not start with a hyphen (would collide with arg parsing).
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', '-foo'), ...
                'mip:init:invalidName');
        end

        function testInit_RejectsTrailingHyphenName(testCase)
            % Names must not end with a hyphen.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', 'foo-'), ...
                'mip:init:invalidName');
        end

        function testInit_RejectsTrailingUnderscoreName(testCase)
            % Names must not end with an underscore.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', 'foo_'), ...
                'mip:init:invalidName');
        end

        function testInit_RejectsDottedName(testCase)
            % Dots are disallowed anywhere in a package name.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', 'my.pkg'), ...
                'mip:init:invalidName');
        end

        function testInit_AcceptsSingleCharName(testCase)
            % A single letter/digit is a valid name (exercises the
            % optional middle+tail group in the regex).
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir, '--name', 'a');

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'a');
        end

        function testInit_AlreadyExistsDoesNotOverwrite(testCase)
            % If mip.yaml already exists, init leaves it untouched.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            yamlPath = fullfile(pkgDir, 'mip.yaml');

            fid = fopen(yamlPath, 'w');
            fprintf(fid, 'name: existing\nversion: "9.9.9"\n');
            fclose(fid);

            origText = fileread(yamlPath);
            mip.init(pkgDir);
            newText = fileread(yamlPath);

            testCase.verifyEqual(newText, origText, ...
                'init must not overwrite an existing mip.yaml');
        end

        function testInit_BlankOptionalFields(testCase)
            % Optional string fields are emitted blank and dependencies
            % defaults to an empty list, so the scaffolded config loads
            % cleanly via read_mip_yaml. Version is set to "unknown".
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.description, '');
            testCase.verifyEqual(cfg.license, '');
            testCase.verifyEqual(cfg.homepage, '');
            testCase.verifyEqual(cfg.repository, '');
            testCase.verifyEqual(cfg.dependencies, {});
            testCase.verifyEqual(cfg.version, 'unknown');
        end

        function testInit_RepositoryOverride(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            url = 'https://example.com/mypkg.zip';

            mip.init(pkgDir, '--repository', url);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.repository, url);
        end

        function testInit_RepositoryMissingValue_Errors(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--repository'), ...
                'mip:init:missingRepositoryValue');
        end

        function testInit_BuildIsAny(testCase)
            % The scaffold emits a single `any`-architecture build entry.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(numel(cfg.builds), 1);
            testCase.verifyEqual(cfg.builds{1}.architectures, {'any'});
        end

        function testInit_CreatesEmptyTestScript(testCase)
            % A zero-byte test_<name>.m is created alongside mip.yaml.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            testScript = fullfile(pkgDir, 'test_mypkg.m');
            testCase.verifyTrue(exist(testScript, 'file') > 0);
            contents = fileread(testScript);
            testCase.verifyEqual(contents, '');
        end

        function testInit_TestScriptReferencedInYaml(testCase)
            % The generated mip.yaml wires test_script to the new test file.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            yamlText = fileread(fullfile(pkgDir, 'mip.yaml'));
            testCase.verifyTrue(contains(yamlText, 'test_script: test_mypkg.m'));
        end

        function testInit_DoesNotOverwriteExistingTestScript(testCase)
            % If test_<name>.m already exists, init must not overwrite it.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            existing = fullfile(pkgDir, 'test_mypkg.m');
            fid = fopen(existing, 'w');
            fprintf(fid, '%% pre-existing test\ndisp(''hi'');\n');
            fclose(fid);
            origText = fileread(existing);

            mip.init(pkgDir);

            newText = fileread(existing);
            testCase.verifyEqual(newText, origText, ...
                'init must not overwrite an existing test script');
        end

        function testInit_AutoAddPathsRoot(testCase)
            % A runtime .m file at the root causes '.' to be auto-included.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            % Place a runtime .m file at the root
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            paths = cellfun(@(s) s.path, cfg.addpaths, 'UniformOutput', false);
            testCase.verifyTrue(any(strcmp(paths, '.')));
        end

        function testInit_AutoAddPathsSkipsTestsAndDocs(testCase)
            % auto_add_paths includes runtime dirs like `src/` but skips
            % well-known non-runtime dirs like `tests/` and `docs/`.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            mkdir(fullfile(pkgDir, 'src'));
            mkdir(fullfile(pkgDir, 'tests'));
            mkdir(fullfile(pkgDir, 'docs'));
            fid = fopen(fullfile(pkgDir, 'src', 'lib.m'), 'w');
            fprintf(fid, 'function y = lib(x); y = x; end\n');
            fclose(fid);
            fid = fopen(fullfile(pkgDir, 'tests', 'a_test.m'), 'w');
            fprintf(fid, '%% test\n');
            fclose(fid);
            fid = fopen(fullfile(pkgDir, 'docs', 'something.m'), 'w');
            fprintf(fid, '%% doc\n');
            fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            paths = cellfun(@(s) s.path, cfg.addpaths, 'UniformOutput', false);
            testCase.verifyTrue(any(strcmp(paths, 'src')));
            testCase.verifyFalse(any(strcmp(paths, 'tests')));
            testCase.verifyFalse(any(strcmp(paths, 'docs')));
        end

        function testInit_EmptyAddpathsRendersAsEmptyList(testCase)
            % Directory with no runtime .m files -> addpaths should be [].
            % auto_add_paths runs *before* the boilerplate test script is
            % created, so the test script does not bring '.' onto the path.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'README.txt'), 'w'); fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.addpaths, {});

            yamlText = fileread(fullfile(pkgDir, 'mip.yaml'));
            testCase.verifyTrue(contains(yamlText, 'addpaths: []'));
        end

        function testInit_AddpathsListMatchesAutoUtil(testCase)
            % The addpaths written into mip.yaml agree with what
            % mip.init.auto_add_paths returns for the same tree.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            mkdir(fullfile(pkgDir, 'src'));
            fid = fopen(fullfile(pkgDir, 'foo.m'), 'w');
            fprintf(fid, 'function y = foo(x); y = x; end\n');
            fclose(fid);
            fid = fopen(fullfile(pkgDir, 'src', 'bar.m'), 'w');
            fprintf(fid, 'function y = bar(x); y = x; end\n');
            fclose(fid);

            % Get expected paths from the utility directly (before init
            % adds the test script, which would change the result).
            expected = mip.init.auto_add_paths(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            paths = cellfun(@(s) s.path, cfg.addpaths, 'UniformOutput', false);
            for k = 1:numel(expected)
                testCase.verifyTrue(any(strcmp(paths, expected{k})), ...
                    sprintf('expected path "%s" missing', expected{k}));
            end
        end

    end
end
