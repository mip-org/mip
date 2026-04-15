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

        function testInit_NoArgsErrors(testCase)
            testCase.verifyError(@() mip.init(), 'mip:init:noPath');
        end

        function testInit_NonexistentPathErrors(testCase)
            testCase.verifyError( ...
                @() mip.init('/nonexistent/path/12345'), ...
                'mip:notAFileOrDirectory');
        end

        function testInit_FileInsteadOfDirErrors(testCase)
            filePath = fullfile(testCase.TestDir, 'a_file.txt');
            fid = fopen(filePath, 'w'); fclose(fid);
            testCase.verifyError(@() mip.init(filePath), 'mip:init:notADirectory');
        end

        function testInit_CreatesMipYaml(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            testCase.verifyTrue(exist(fullfile(pkgDir, 'mip.yaml'), 'file') > 0);
        end

        function testInit_DefaultsNameToDirBasename(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'mypkg');
        end

        function testInit_NameOverride(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir, '--name', 'overridden');

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'overridden');
        end

        function testInit_RejectsInvalidName(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', 'bad name'), ...
                'mip:init:invalidName');
        end

        function testInit_RejectsDotDotName(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', '..'), ...
                'mip:init:invalidName');
        end

        function testInit_AlreadyExistsDoesNotOverwrite(testCase)
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
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.description, '');
            testCase.verifyEqual(cfg.license, '');
            testCase.verifyEqual(cfg.homepage, '');
            testCase.verifyEqual(cfg.repository, '');
            testCase.verifyEqual(cfg.dependencies, {});
        end

        function testInit_BuildIsAny(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(numel(cfg.builds), 1);
            testCase.verifyEqual(cfg.builds{1}.architectures, {'any'});
        end

        function testInit_CreatesEmptyTestScript(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            testScript = fullfile(pkgDir, 'test_mypkg.m');
            testCase.verifyTrue(exist(testScript, 'file') > 0);
            contents = fileread(testScript);
            testCase.verifyEqual(contents, '');
        end

        function testInit_TestScriptReferencedInYaml(testCase)
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            yamlText = fileread(fullfile(pkgDir, 'mip.yaml'));
            testCase.verifyTrue(contains(yamlText, 'test_script: test_mypkg.m'));
        end

        function testInit_DoesNotOverwriteExistingTestScript(testCase)
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
