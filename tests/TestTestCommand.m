classdef TestTestCommand < matlab.unittest.TestCase
%TESTTESTCOMMAND   Tests for mip.test functionality.

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

        function testTest_NotInstalled(testCase)
            testCase.verifyError(@() mip.test('nonexistent'), 'mip:test:notInstalled');
        end

        function testTest_NoTestScript(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'notestpkg');
            % Create the source subdirectory expected by get_source_dir
            mkdir(fullfile(testCase.TestRoot, 'packages', 'gh', 'mip-org', 'core', 'notestpkg', 'notestpkg'));
            output = evalc('mip.test(''mip-org/core/notestpkg'')');
            testCase.verifyTrue(contains(output, 'No test script'));
        end

        function testTest_RunsTestScript(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core','testpkg', 'run_test.m', false);
            output = evalc('mip.test(''mip-org/core/testpkg'')');
            testCase.verifyTrue(contains(output, 'Running test script'));
        end

        function testTest_FailingScriptErrors(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core','failpkg', 'run_test.m', true);
            testCase.verifyError(@() mip.test('mip-org/core/failpkg'), 'mip:test:failed');
        end

        function testTest_LoadsPackageIfNotLoaded(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core','autoloadpkg', 'run_test.m', false);
            testCase.verifyFalse(mip.state.is_loaded('mip-org/core/autoloadpkg'));
            evalc('mip.test(''mip-org/core/autoloadpkg'')');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/autoloadpkg'));
        end

        function testTest_BareNameResolution(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core','barepkg', 'run_test.m', false);
            output = evalc('mip.test(''barepkg'')');
            testCase.verifyTrue(contains(output, 'Running test script'));
        end

        function testTest_PrefersLoadedOverInstalledCore(testCase)
            % Both core and staging install a package called "shared".
            % The core copy passes, the staging copy fails. After loading
            % the staging copy, "mip test shared" must run the loaded
            % staging copy (and therefore fail), not the unloaded core
            % copy that resolve_bare_name would prefer.
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'shared', 'run_test.m', false);
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'staging', 'shared', 'run_test.m', true);
            evalc('mip.load(''mip-org/staging/shared'')');
            testCase.verifyError(@() mip.test('shared'), 'mip:test:failed');
        end

        function testTest_MostRecentlyLoadedAmongMultiple(testCase)
            % Three installed copies of "shared". core passes, alpha
            % passes, beta fails. Loading core then alpha then beta means
            % beta is the most recently loaded — "mip test shared" must
            % run beta and fail.
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'shared', 'run_test.m', false);
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'alpha', 'shared', 'run_test.m', false);
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'beta', 'shared', 'run_test.m', true);
            evalc('mip.load(''mip-org/core/shared'')');
            evalc('mip.load(''mip-org/alpha/shared'')');
            evalc('mip.load(''mip-org/beta/shared'')');
            testCase.verifyError(@() mip.test('shared'), 'mip:test:failed');
        end

        function testTest_FallsBackToCoreWhenNoneLoaded(testCase)
            % With nothing loaded, bare-name "mip test shared" falls back
            % to resolve_bare_name which prefers gh/mip-org/core. The
            % core copy passes; the staging copy would fail.
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'shared', 'run_test.m', false);
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'staging', 'shared', 'run_test.m', true);
            output = evalc('mip.test(''shared'')');
            testCase.verifyTrue(contains(output, 'mip-org/core/shared'));
            testCase.verifyTrue(contains(output, 'Running test script'));
        end

        function testTest_FqnIgnoresLoadedPriority(testCase)
            % Even when a non-core copy is loaded, an explicit FQN must
            % resolve to that exact FQN — not the most recently loaded.
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'shared', 'run_test.m', false);
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'staging', 'shared', 'run_test.m', true);
            evalc('mip.load(''mip-org/staging/shared'')');
            output = evalc('mip.test(''mip-org/core/shared'')');
            testCase.verifyTrue(contains(output, 'mip-org/core/shared'));
            testCase.verifyTrue(contains(output, 'Running test script'));
        end

        function testTest_PublishesFqnContext(testCase)
            % While the script runs, mip.test.get_fqn() names the package
            % under test, and effective_arch/has_mex resolve it (architecture
            % 'any' here, so no MEX). The script asserts this and errors --
            % failing the test -- if the context is wrong.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'ctxpkg');
            writeTestScript(pkgDir, 'ctxpkg', 'run_test.m', { ...
                'fqn = mip.test.get_fqn();', ...
                'assert(~isempty(fqn));', ...
                'assert(strcmp(mip.build.effective_arch(fqn), ''any''));', ...
                'assert(~mip.build.has_mex(fqn));', ...
                'fprintf(''ctx ok\n'');'});
            output = evalc('mip.test(''mip-org/core/ctxpkg'')');
            testCase.verifyTrue(contains(output, 'ctx ok'));
        end

        function testTest_ClearsContextAfterRun(testCase)
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'donepkg', 'run_test.m', false);
            mip.test('mip-org/core/donepkg');
            testCase.verifyError(@() mip.test.get_fqn(), 'mip:test:noContext');
        end

        function testTest_ClearsContextAfterFailure(testCase)
            createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'failctx', 'run_test.m', true);
            testCase.verifyError(@() mip.test('mip-org/core/failctx'), 'mip:test:failed');
            testCase.verifyError(@() mip.test.get_fqn(), 'mip:test:noContext');
        end

        function testTest_GetFqnErrorsOutsideTest(testCase)
            testCase.verifyError(@() mip.test.get_fqn(), 'mip:test:noContext');
        end

        function testTest_EffectiveArchExplicitFqn(testCase)
            % No `mip test` needed: resolve a package's effective arch by name.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'archpkg');
            testCase.verifyEqual(mip.build.effective_arch('mip-org/core/archpkg'), 'any');
            testCase.verifyFalse(mip.build.has_mex('mip-org/core/archpkg'));
        end

        function testTest_ListMexEmptyWhenNoMex(testCase)
            % A package that ships no MEX -> empty list, has_mex false.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'nomexpkg');
            testCase.verifyEmpty(mip.build.list_mex('mip-org/core/nomexpkg'));
            testCase.verifyFalse(mip.build.has_mex('mip-org/core/nomexpkg'));
        end

        function testTest_ListMexFindsMexFiles(testCase)
            % A fake MEX (current-arch extension) in the source dir is listed
            % by base name, and has_mex is then true.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mexpkg');
            fid = fopen(fullfile(pkgDir, 'mexpkg', ['foo.' mexext]), 'w');
            fclose(fid);
            built = mip.build.list_mex('mip-org/core/mexpkg');
            testCase.verifyTrue(ismember('foo', built));
            testCase.verifyTrue(mip.build.has_mex('mip-org/core/mexpkg'));
        end

        function testTest_BuildHelpersRejectBareName(testCase)
            % Downstream utilities require an fqn; a bare name is rejected so a
            % call site can't silently pick the wrong package among duplicates.
            testCase.verifyError(@() mip.build.list_mex('barepkg'), 'mip:invalidFqn');
            testCase.verifyError(@() mip.build.has_mex('barepkg'), 'mip:invalidFqn');
            testCase.verifyError(@() mip.build.effective_arch('barepkg'), 'mip:invalidFqn');
        end

    end
end


function pkgDir = createTestPackageWithTestScript(rootDir, owner, channel, pkgName, testScriptName, shouldFail)
%CREATETESTPACKAGEWITHTESTSCRIPT   Create a test package with a test_script field.

    pkgDir = createTestPackage(rootDir, owner, channel, pkgName);

    % Create the source subdirectory
    srcDir = fullfile(pkgDir, pkgName);
    if ~exist(srcDir, 'dir')
        mkdir(srcDir);
    end

    % Update mip.json to include test_script
    jsonPath = fullfile(pkgDir, 'mip.json');
    jsonText = fileread(jsonPath);
    jsonData = jsondecode(jsonText);
    jsonData.test_script = testScriptName;
    fid = fopen(jsonPath, 'w');
    fwrite(fid, jsonencode(jsonData));
    fclose(fid);

    % Create the test script in the source subdirectory
    scriptPath = fullfile(srcDir, testScriptName);
    fid = fopen(scriptPath, 'w');
    if shouldFail
        fprintf(fid, 'error(''test:intentionalFail'', ''Test intentionally failed'');\n');
    else
        fprintf(fid, 'fprintf(''Tests passed.\\n'');\n');
    end
    fclose(fid);
end

function writeTestScript(pkgDir, pkgName, scriptName, lines)
%WRITETESTSCRIPT   Point a package's mip.json at a test_script and write its
% body from a cell array of source lines.

    jsonPath = fullfile(pkgDir, 'mip.json');
    jsonData = jsondecode(fileread(jsonPath));
    jsonData.test_script = scriptName;
    fid = fopen(jsonPath, 'w');
    fwrite(fid, jsonencode(jsonData));
    fclose(fid);

    srcDir = fullfile(pkgDir, pkgName);
    if ~exist(srcDir, 'dir')
        mkdir(srcDir);
    end
    fid = fopen(fullfile(srcDir, scriptName), 'w');
    for i = 1:numel(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fclose(fid);
end
