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
            mkdir(fullfile(testCase.TestRoot, 'packages', 'mip-org', 'core', 'notestpkg', 'notestpkg'));
            output = evalc('mip.test(''mip-org/core/notestpkg'')');
            testCase.verifyTrue(contains(output, 'No test script'));
        end

        function testTest_RunsTestScript(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'testpkg', 'run_test.m', false);
            output = evalc('mip.test(''mip-org/core/testpkg'')');
            testCase.verifyTrue(contains(output, 'Running test script'));
        end

        function testTest_FailingScriptErrors(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'failpkg', 'run_test.m', true);
            testCase.verifyError(@() mip.test('mip-org/core/failpkg'), 'mip:test:failed');
        end

        function testTest_LoadsPackageIfNotLoaded(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'autoloadpkg', 'run_test.m', false);
            testCase.verifyFalse(mip.state.is_loaded('mip-org/core/autoloadpkg'));
            evalc('mip.test(''mip-org/core/autoloadpkg'')');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/autoloadpkg'));
        end

        function testTest_BareNameResolution(testCase)
            pkgDir = createTestPackageWithTestScript(testCase.TestRoot, ...
                'mip-org', 'core', 'barepkg', 'run_test.m', false);
            output = evalc('mip.test(''barepkg'')');
            testCase.verifyTrue(contains(output, 'Running test script'));
        end

    end
end


function pkgDir = createTestPackageWithTestScript(rootDir, org, channel, pkgName, testScriptName, shouldFail)
%CREATETESTPACKAGEWITHTESTSCRIPT   Create a test package with a test_script field.

    pkgDir = createTestPackage(rootDir, org, channel, pkgName);

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
