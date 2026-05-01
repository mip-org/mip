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

        function testInit_RejectsUppercaseName(testCase)
            % Canonical names must be lowercase.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            testCase.verifyError( ...
                @() mip.init(pkgDir, '--name', 'MyPkg'), ...
                'mip:init:invalidName');
        end

        function testInit_LowercasesUppercaseDirBasename(testCase)
            % When --name is omitted and the directory basename contains
            % uppercase letters, init lowercases the basename to produce
            % a canonical package name. (Directory basenames with other
            % non-canonical characters — dots, spaces, etc. — still
            % error; the user can use --name to override.)
            pkgDir = fullfile(testCase.TestDir, 'MyPkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'mypkg');
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
            % cleanly via read_mip_yaml.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.description, '');
            testCase.verifyEqual(cfg.license, '');
            testCase.verifyEqual(cfg.homepage, '');
            testCase.verifyEqual(cfg.repository, '');
            testCase.verifyEqual(cfg.dependencies, {});
            testCase.verifyEqual(cfg.version, '');
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
            paths = cellfun(@(s) s.path, cfg.paths, 'UniformOutput', false);
            testCase.verifyTrue(any(strcmp(paths, '.')));
        end

        function testInit_AutoAddPathsRoutesTestsAndExamples(testCase)
            % auto_add_paths includes runtime dirs like `src/` in the
            % main paths list, routes tests/ and examples/ into
            % extra_paths groups, and still skips docs/ entirely.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            mkdir(fullfile(pkgDir, 'src'));
            mkdir(fullfile(pkgDir, 'tests'));
            mkdir(fullfile(pkgDir, 'examples'));
            mkdir(fullfile(pkgDir, 'docs'));
            fid = fopen(fullfile(pkgDir, 'src', 'lib.m'), 'w');
            fprintf(fid, 'function y = lib(x); y = x; end\n');
            fclose(fid);
            fid = fopen(fullfile(pkgDir, 'tests', 'a_test.m'), 'w');
            fprintf(fid, '%% test\n');
            fclose(fid);
            fid = fopen(fullfile(pkgDir, 'examples', 'ex1.m'), 'w');
            fprintf(fid, '%% example\n');
            fclose(fid);
            fid = fopen(fullfile(pkgDir, 'docs', 'something.m'), 'w');
            fprintf(fid, '%% doc\n');
            fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            paths = cellfun(@(s) s.path, cfg.paths, 'UniformOutput', false);

            % src/ is main runtime; docs/ is skipped; tests/ and
            % examples/ move to extra_paths.
            testCase.verifyTrue(any(strcmp(paths, 'src')));
            testCase.verifyFalse(any(strcmp(paths, 'tests')));
            testCase.verifyFalse(any(strcmp(paths, 'examples')));
            testCase.verifyFalse(any(strcmp(paths, 'docs')));

            testCase.verifyTrue(isfield(cfg.extra_paths, 'tests'));
            testCase.verifyTrue(isfield(cfg.extra_paths, 'examples'));
            testCase.verifyFalse(isfield(cfg.extra_paths, 'docs'));
            testCase.verifyEqual(cfg.extra_paths.tests{1}.path, 'tests');
            testCase.verifyEqual(cfg.extra_paths.examples{1}.path, 'examples');
        end

        function testInit_AutoAddPathsBenchmarksGroup(testCase)
            % Benchmarks is its own third group (not lumped with
            % examples or tests) because benchmarks can be heavy and
            % users often want examples without them or vice versa.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            mkdir(fullfile(pkgDir, 'benchmarks'));
            fid = fopen(fullfile(pkgDir, 'benchmarks', 'bench_a.m'), 'w');
            fprintf(fid, '%% bench\n');
            fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyTrue(isfield(cfg.extra_paths, 'benchmarks'));
            testCase.verifyEqual(cfg.extra_paths.benchmarks{1}.path, 'benchmarks');
        end

        function testInit_NoExtraPathsOmitsSection(testCase)
            % A package with no tests/examples/benchmarks dirs should
            % not get an `extra_paths:` section in the generated yaml.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'lib.m'), 'w');
            fprintf(fid, 'function y = lib(x); y = x; end\n');
            fclose(fid);

            mip.init(pkgDir);

            yamlText = fileread(fullfile(pkgDir, 'mip.yaml'));
            testCase.verifyFalse(contains(yamlText, 'extra_paths:'));
        end

        function testInit_EmptyPathsRendersAsEmptyList(testCase)
            % Directory with no runtime .m files -> paths should be [].
            % auto_add_paths runs *before* the boilerplate test script is
            % created, so the test script does not bring '.' onto the path.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'README.txt'), 'w'); fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.paths, {});

            yamlText = fileread(fullfile(pkgDir, 'mip.yaml'));
            testCase.verifyTrue(contains(yamlText, 'paths: []'));
        end

        function testInit_GitConfigFillsNameAndRepository(testCase)
            % If targetDir contains a .git/config with an origin URL,
            % init derives the package name from the URL and writes the
            % URL into `repository`. The folder basename is ignored
            % (folder is "mypkg", git repo is "chebfun").
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            writeGitConfigOrigin(pkgDir, 'https://github.com/chebfun/chebfun');

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'chebfun');
            testCase.verifyEqual(cfg.repository, ...
                'https://github.com/chebfun/chebfun');
        end

        function testInit_GitConfigStripsDotGitFromName(testCase)
            % An origin URL ending in .git keeps the suffix in the
            % `repository` field (canonical clone URL) but does not
            % include it in the derived package name.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            writeGitConfigOrigin(pkgDir, 'https://github.com/owner/myrepo.git');

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'myrepo');
            testCase.verifyEqual(cfg.repository, ...
                'https://github.com/owner/myrepo.git');
        end

        function testInit_GitConfigSshUrl(testCase)
            % SSH-style URLs (git@host:owner/repo.git) parse correctly:
            % the URL is preserved in `repository` and the repo name is
            % the trailing path segment with .git stripped.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            writeGitConfigOrigin(pkgDir, 'git@github.com:owner/sshrepo.git');

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'sshrepo');
            testCase.verifyEqual(cfg.repository, ...
                'git@github.com:owner/sshrepo.git');
        end

        function testInit_GitConfigLowercasesName(testCase)
            % An uppercase repo name is lowercased to produce a
            % canonical package name (mirrors the dir-basename path).
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            writeGitConfigOrigin(pkgDir, 'https://github.com/Owner/MyRepo');

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'myrepo');
        end

        function testInit_GitConfigNameOverrideStillWins(testCase)
            % --name continues to take precedence over the git-derived
            % name (and the dir basename).
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            writeGitConfigOrigin(pkgDir, 'https://github.com/owner/repo');

            mip.init(pkgDir, '--name', 'overridden');

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'overridden');
            % Repository is still auto-filled when --name is used.
            testCase.verifyEqual(cfg.repository, ...
                'https://github.com/owner/repo');
        end

        function testInit_GitConfigRepositoryOverrideStillWins(testCase)
            % --repository continues to take precedence over the
            % git-derived URL (even an empty string passed by the user).
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            writeGitConfigOrigin(pkgDir, 'https://github.com/owner/repo');

            url = 'https://example.com/custom.zip';
            mip.init(pkgDir, '--repository', url);

            cfg = mip.config.read_mip_yaml(pkgDir);
            % Name is still auto-derived from the git config.
            testCase.verifyEqual(cfg.name, 'repo');
            testCase.verifyEqual(cfg.repository, url);
        end

        function testInit_GitConfigNoRemoteFallsBack(testCase)
            % A .git/config with no remote URL leaves `repository`
            % blank and falls back to the directory basename for the
            % package name.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            mkdir(fullfile(pkgDir, '.git'));
            fid = fopen(fullfile(pkgDir, '.git', 'config'), 'w');
            fprintf(fid, '[core]\n\trepositoryformatversion = 0\n');
            fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'mypkg');
            testCase.verifyEqual(cfg.repository, '');
        end

        function testInit_GitConfigPrefersOriginOverOtherRemotes(testCase)
            % When several remotes are listed, origin wins regardless
            % of file order.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            mkdir(fullfile(pkgDir, '.git'));
            fid = fopen(fullfile(pkgDir, '.git', 'config'), 'w');
            fprintf(fid, '[remote "upstream"]\n');
            fprintf(fid, '\turl = https://github.com/upstream/wrong\n');
            fprintf(fid, '[remote "origin"]\n');
            fprintf(fid, '\turl = https://github.com/me/right\n');
            fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'right');
            testCase.verifyEqual(cfg.repository, ...
                'https://github.com/me/right');
        end

        function testInit_GitConfigFallsBackToFirstRemoteWhenNoOrigin(testCase)
            % If no [remote "origin"] section exists, the first remote
            % seen in file order is used.
            pkgDir = fullfile(testCase.TestDir, 'mypkg');
            mkdir(pkgDir);
            mkdir(fullfile(pkgDir, '.git'));
            fid = fopen(fullfile(pkgDir, '.git', 'config'), 'w');
            fprintf(fid, '[remote "upstream"]\n');
            fprintf(fid, '\turl = https://github.com/upstream/first\n');
            fprintf(fid, '[remote "fork"]\n');
            fprintf(fid, '\turl = https://github.com/fork/second\n');
            fclose(fid);

            mip.init(pkgDir);

            cfg = mip.config.read_mip_yaml(pkgDir);
            testCase.verifyEqual(cfg.name, 'first');
            testCase.verifyEqual(cfg.repository, ...
                'https://github.com/upstream/first');
        end

        function testInit_GitInfoHelperReturnsEmptyWhenNoGit(testCase)
            % Direct unit test for the helper: a directory with no
            % .git/ returns empty strings.
            pkgDir = fullfile(testCase.TestDir, 'plain');
            mkdir(pkgDir);

            [name, url] = mip.init.git_info(pkgDir);
            testCase.verifyEqual(name, '');
            testCase.verifyEqual(url, '');
        end

        function testInit_PathsListMatchesAutoUtil(testCase)
            % The paths written into mip.yaml agree with what
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
            paths = cellfun(@(s) s.path, cfg.paths, 'UniformOutput', false);
            for k = 1:numel(expected)
                testCase.verifyTrue(any(strcmp(paths, expected{k})), ...
                    sprintf('expected path "%s" missing', expected{k}));
            end
        end

    end
end


function writeGitConfigOrigin(pkgDir, url)
% Helper: write a minimal .git/config under pkgDir whose [remote "origin"]
% has the given url.
mkdir(fullfile(pkgDir, '.git'));
fid = fopen(fullfile(pkgDir, '.git', 'config'), 'w');
fprintf(fid, '[core]\n\trepositoryformatversion = 0\n');
fprintf(fid, '[remote "origin"]\n');
fprintf(fid, '\turl = %s\n', url);
fprintf(fid, '\tfetch = +refs/heads/*:refs/remotes/origin/*\n');
fclose(fid);
end
