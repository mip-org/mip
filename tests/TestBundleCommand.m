classdef TestBundleCommand < matlab.unittest.TestCase
%TESTBUNDLECOMMAND   Tests for mip.bundle functionality.

    properties
        SourceDir
        OutputDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.SourceDir = [tempname '_mip_src'];
            testCase.OutputDir = [tempname '_mip_out'];
            mkdir(testCase.SourceDir);
            mkdir(testCase.OutputDir);
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            if exist(testCase.SourceDir, 'dir')
                rmdir(testCase.SourceDir, 's');
            end
            if exist(testCase.OutputDir, 'dir')
                rmdir(testCase.OutputDir, 's');
            end
        end
    end

    methods (Test)

        function testBundle_ProducesMhlFile(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            mhlFiles = dir(fullfile(testCase.OutputDir, '*.mhl'));
            testCase.verifyNotEmpty(mhlFiles, '.mhl file should be created');
        end

        function testBundle_OutputFilenameFormat(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', '2.0.0');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            expected = 'mypkg-2.0.0-any.mhl';
            testCase.verifyTrue(exist(fullfile(testCase.OutputDir, expected), 'file') > 0, ...
                sprintf('Expected file %s to exist', expected));
        end

        function testBundle_ProducesMipJson(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            jsonFiles = dir(fullfile(testCase.OutputDir, '*.mip.json'));
            testCase.verifyNotEmpty(jsonFiles, '.mip.json metadata should be created');
        end

        function testBundle_MipJsonContainsCorrectName(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            jsonFiles = dir(fullfile(testCase.OutputDir, '*.mip.json'));
            jsonText = fileread(fullfile(testCase.OutputDir, jsonFiles(1).name));
            jsonData = jsondecode(jsonText);
            testCase.verifyEqual(jsonData.name, 'mypkg');
        end

        function testBundle_NoDirectoryErrors(testCase)
            testCase.verifyError(@() mip.bundle(), 'mip:bundle:noDirectory');
        end

        function testBundle_NonexistentDirectoryErrors(testCase)
            testCase.verifyError( ...
                @() mip.bundle('/nonexistent/path/12345'), ...
                'mip:notAFileOrDirectory');
        end

        function testBundle_NoMipYamlErrors(testCase)
            emptyDir = fullfile(testCase.SourceDir, 'emptypkg');
            mkdir(emptyDir);
            testCase.verifyError(@() mip.bundle(emptyDir), 'mip:bundle:noMipYaml');
        end

        function testBundle_WithArchOverride(testCase)
            % When the build entry has [any], --arch still matches as 'any'
            % since the build's effective architecture is 'any'.
            % The --arch flag selects which build entry to match.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', '1.0.0');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'linux_x86_64');

            expected = 'mypkg-1.0.0-any.mhl';
            testCase.verifyTrue(exist(fullfile(testCase.OutputDir, expected), 'file') > 0, ...
                sprintf('Expected file %s to exist', expected));
        end

        function testBundle_MhlIsValidZip(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            mhlFiles = dir(fullfile(testCase.OutputDir, '*.mhl'));
            mhlPath = fullfile(testCase.OutputDir, mhlFiles(1).name);

            % Verify we can list the contents (valid zip)
            extractDir = [tempname '_extract'];
            unzip(mhlPath, extractDir);
            testCase.addTeardown(@() rmdir(extractDir, 's'));

            testCase.verifyTrue(exist(fullfile(extractDir, 'mip.json'), 'file') > 0);
            testCase.verifyTrue(exist(fullfile(extractDir, 'load_package.m'), 'file') > 0);
            testCase.verifyTrue(exist(fullfile(extractDir, 'unload_package.m'), 'file') > 0);
            testCase.verifyTrue(exist(fullfile(extractDir, 'mypkg'), 'dir') > 0);
        end

    end
end
