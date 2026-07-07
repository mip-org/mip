classdef TestReadVersion < matlab.unittest.TestCase
%TESTREADVERSION   Tests for mip.self.read_version (backs `mip version`
%   and the `mip info` self display).

    properties
        TestDir
    end

    methods (TestMethodSetup)
        function setupTestDir(testCase)
            testCase.TestDir = [tempname '_mip_read_version_test'];
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

        function testInstalledLayoutReadsMipJsonVersion(testCase)
            % Installed mip@main: the channel build records version "main"
            % in mip.json one level above the source dir, while the
            % source's mip.yaml version is blank. mip.json must win
            % (regression test for issue #299).
            sourceDir = testCase.createInstalledLayout('mip', 'main');
            writeMipYaml(sourceDir, 'mip', '');

            v = mip.self.read_version(sourceDir);
            testCase.verifyEqual(v, 'main');
        end

        function testInstalledLayoutWithoutMipYaml(testCase)
            % mip.json alone is sufficient in the installed layout.
            sourceDir = testCase.createInstalledLayout('mip', '0.4.1');

            v = mip.self.read_version(sourceDir);
            testCase.verifyEqual(v, '0.4.1');
        end

        function testSourceCheckoutReadsMipYaml(testCase)
            % A source checkout has no mip.json above it; the version
            % comes from mip.yaml.
            sourceDir = fullfile(testCase.TestDir, 'mip');
            mkdir(sourceDir);
            writeMipYaml(sourceDir, 'mip', '1.2.3');

            v = mip.self.read_version(sourceDir);
            testCase.verifyEqual(v, '1.2.3');
        end

        function testSourceCheckoutBlankVersionIsUnspecified(testCase)
            % mip.yaml's version field is optional; a blank version is
            % reported as 'unspecified', not as an empty string.
            sourceDir = fullfile(testCase.TestDir, 'mip');
            mkdir(sourceDir);
            writeMipYaml(sourceDir, 'mip', '');

            v = mip.self.read_version(sourceDir);
            testCase.verifyEqual(v, 'unspecified');
        end

        function testUnrelatedParentMipJsonIgnored(testCase)
            % A source checkout sitting inside a directory that happens to
            % contain some other package's mip.json must not pick up that
            % version: the mip.json "name" does not match the source dir.
            writeMipJson(testCase.TestDir, 'otherpkg', '9.9.9');
            sourceDir = fullfile(testCase.TestDir, 'mip');
            mkdir(sourceDir);
            writeMipYaml(sourceDir, 'mip', '2.0.0');

            v = mip.self.read_version(sourceDir);
            testCase.verifyEqual(v, '2.0.0');
        end

        function testNoMetadataErrors(testCase)
            sourceDir = fullfile(testCase.TestDir, 'mip');
            mkdir(sourceDir);

            testCase.verifyError(@() mip.self.read_version(sourceDir), ...
                'mip:version:noMetadata');
        end

        function testMipVersionReturnsNonEmpty(testCase)
            % Integration: mip.version() resolves against the running copy
            % of mip and always returns a non-empty string.
            v = mip.version();
            testCase.verifyTrue(ischar(v) && ~isempty(v), ...
                'mip.version() should return a non-empty char');
        end

    end

    methods
        function sourceDir = createInstalledLayout(testCase, pkgName, version)
            % Fake installed layout: <pkgDir>/mip.json + <pkgDir>/<name>/.
            pkgDir = fullfile(testCase.TestDir, 'packages', 'gh', ...
                'mip-org', 'core', pkgName);
            sourceDir = fullfile(pkgDir, pkgName);
            mkdir(sourceDir);
            writeMipJson(pkgDir, pkgName, version);
        end
    end

end


function writeMipJson(dirPath, name, version)
    data = struct('name', name, 'version', version, ...
                  'dependencies', {reshape({}, 0, 1)}, 'paths', {{'.'}});
    fid = fopen(fullfile(dirPath, 'mip.json'), 'w');
    fwrite(fid, jsonencode(data));
    fclose(fid);
end


function writeMipYaml(dirPath, name, version)
    fid = fopen(fullfile(dirPath, 'mip.yaml'), 'w');
    fprintf(fid, 'name: %s\nversion: "%s"\n', name, version);
    fclose(fid);
end
