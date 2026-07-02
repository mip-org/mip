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

        function testBundle_HyphenInNameEncodedAsUnderscoreInFilename(testCase)
            % Canonical names may contain '-', but the filename uses '-'
            % as a field separator, so the name is encoded with '_' in
            % the filename. The canonical name is preserved in mip.json.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'foo-bar', 'version', '1.0.0');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            expected = 'foo_bar-1.0.0-any.mhl';
            testCase.verifyTrue(exist(fullfile(testCase.OutputDir, expected), 'file') > 0, ...
                sprintf('Expected file %s to exist', expected));

            jsonFiles = dir(fullfile(testCase.OutputDir, '*.mip.json'));
            jsonText = fileread(fullfile(testCase.OutputDir, jsonFiles(1).name));
            jsonData = jsondecode(jsonText);
            testCase.verifyEqual(jsonData.name, 'foo-bar', ...
                'Canonical name must be preserved in mip.json');
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
            testCase.verifyTrue(exist(fullfile(extractDir, 'mypkg'), 'dir') > 0);
        end

        function testBundle_BlankVersionRecordsUnspecified(testCase)
            % A blank mip.yaml version with no channel release-version
            % override is recorded as the placeholder 'unspecified' in
            % mip.json and the .mhl filename.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', '');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            expected = 'mypkg-unspecified-any.mhl';
            testCase.verifyTrue(exist(fullfile(testCase.OutputDir, expected), 'file') > 0, ...
                sprintf('Expected file %s to exist', expected));

            jsonText = fileread(fullfile(testCase.OutputDir, [expected '.mip.json']));
            jsonData = jsondecode(jsonText);
            testCase.verifyEqual(jsonData.version, 'unspecified');
        end

        function testBundle_NonNumericVersionErrors(testCase)
            % A non-empty mip.yaml version must be numeric.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', 'main');

            testCase.verifyError( ...
                @() mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any'), ...
                'mip:invalidMipYaml');
        end

        function testBundle_NonNumericReleaseVersionTakesPrecedence(testCase)
            % A non-numeric channel release version (e.g. a branch name)
            % overrides mip.yaml's numeric version in mip.json.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', '1.2.3');
            writeReleaseVersion(srcDir, 'main');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            expected = 'mypkg-main-any.mhl';
            testCase.verifyTrue(exist(fullfile(testCase.OutputDir, expected), 'file') > 0, ...
                sprintf('Expected file %s to exist', expected));

            jsonText = fileread(fullfile(testCase.OutputDir, [expected '.mip.json']));
            jsonData = jsondecode(jsonText);
            testCase.verifyEqual(jsonData.version, 'main');
        end

        function testBundle_MatchingNumericReleaseVersionOk(testCase)
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', '1.2.3');
            writeReleaseVersion(srcDir, '1.2.3');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            expected = 'mypkg-1.2.3-any.mhl';
            testCase.verifyTrue(exist(fullfile(testCase.OutputDir, expected), 'file') > 0, ...
                sprintf('Expected file %s to exist', expected));
        end

        function testBundle_ConflictingNumericReleaseVersionErrors(testCase)
            % A numeric release version must match mip.yaml's version.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', '1.2.3');
            writeReleaseVersion(srcDir, '2.0.0');

            testCase.verifyError( ...
                @() mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any'), ...
                'mip:build:versionMismatch');
        end

        function testBundle_NumericReleaseVersionWithBlankYamlVersionOk(testCase)
            % When mip.yaml's version is blank, the release directory
            % supplies the version outright.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg', 'version', '');
            writeReleaseVersion(srcDir, '3.1.4');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            expected = 'mypkg-3.1.4-any.mhl';
            testCase.verifyTrue(exist(fullfile(testCase.OutputDir, expected), 'file') > 0, ...
                sprintf('Expected file %s to exist', expected));

            jsonText = fileread(fullfile(testCase.OutputDir, [expected '.mip.json']));
            jsonData = jsondecode(jsonText);
            testCase.verifyEqual(jsonData.version, '3.1.4');
        end

        function testBundle_MipJsonContainsPaths(testCase)
            % The bundled mip.json must carry a "paths" array so mip.load
            % can addpath the right source subdirs at load time.
            srcDir = createTestSourcePackage(testCase.SourceDir, 'mypkg');
            mip.bundle(srcDir, '--output', testCase.OutputDir, '--arch', 'any');

            jsonFiles = dir(fullfile(testCase.OutputDir, '*.mip.json'));
            jsonText = fileread(fullfile(testCase.OutputDir, jsonFiles(1).name));
            jsonData = jsondecode(jsonText);
            testCase.verifyTrue(isfield(jsonData, 'paths'));
            % jsondecode may return a scalar string or a cell array for a
            % single-element JSON array -- normalize before comparing.
            paths = jsonData.paths;
            if ~iscell(paths)
                paths = {paths};
            end
            testCase.verifyEqual(paths, {'.'}, ...
                'createTestSourcePackage declares a single addpath "." so paths should be a one-element list');
        end

    end
end

function writeReleaseVersion(srcDir, releaseVersion)
% Drop the .release_version side file the channel build uses to pass the
% release-directory name to mip bundle.
    fid = fopen(fullfile(srcDir, '.release_version'), 'w');
    fwrite(fid, releaseVersion);
    fclose(fid);
end
