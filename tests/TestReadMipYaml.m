classdef TestReadMipYaml < matlab.unittest.TestCase
%TESTREADMIPYAML   Tests for mip.config.read_mip_yaml.

    properties
        TestDir
    end

    methods (TestMethodSetup)
        function setupTestDir(testCase)
            testCase.TestDir = [tempname '_mip_yaml_test'];
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

        function testReadMinimalYaml(testCase)
            writeYaml(testCase.TestDir, ...
                'name: testpkg\nversion: "1.0.0"\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.name, 'testpkg');
            testCase.verifyEqual(cfg.version, '1.0.0');
            testCase.verifyEqual(cfg.dependencies, {});
            testCase.verifyEqual(cfg.paths, {});
        end

        function testReadYamlWithDependencies(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "2.0.0"\ndependencies: [depA, depB]\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.name, 'mypkg');
            testCase.verifyEqual(sort(cfg.dependencies), sort({'depA', 'depB'}));
        end

        function testReadYamlWithPaths(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "1.0.0"\npaths:\n  - path: "."\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyFalse(isempty(cfg.paths));
        end

        function testReadYamlExtraPathsDefaultsToEmptyStruct(testCase)
            % When the yaml omits extra_paths entirely, read_mip_yaml
            % still populates the field with an empty struct so
            % downstream code can iterate fieldnames() unconditionally.
            writeYaml(testCase.TestDir, 'name: mypkg\nversion: "1.0.0"\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyTrue(isstruct(cfg.extra_paths));
            testCase.verifyTrue(isempty(fieldnames(cfg.extra_paths)));
        end

        function testReadYamlExtraPathsWithGroups(testCase)
            % A populated extra_paths mapping should parse into a struct
            % whose fields are the group names and whose values are
            % cell arrays of entries shaped like top-level paths (each
            % entry a struct with a .path field, for the path: "..." form).
            writeYaml(testCase.TestDir, ...
                ['name: mypkg\nversion: "1.0.0"\n' ...
                 'extra_paths:\n' ...
                 '  examples:\n' ...
                 '    - path: "examples"\n' ...
                 '  tests:\n' ...
                 '    - path: "tests"\n']);

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyTrue(isfield(cfg.extra_paths, 'examples'));
            testCase.verifyTrue(isfield(cfg.extra_paths, 'tests'));
            testCase.verifyEqual(cfg.extra_paths.examples{1}.path, 'examples');
            testCase.verifyEqual(cfg.extra_paths.tests{1}.path, 'tests');
        end

        function testReadYamlExtraPathsRejectsNonMapping(testCase)
            % If the user writes `extra_paths:` as a sequence instead of
            % a mapping, surface a clear invalidMipYaml error rather
            % than letting a confusing downstream failure happen.
            writeYaml(testCase.TestDir, ...
                ['name: mypkg\nversion: "1.0.0"\n' ...
                 'extra_paths:\n' ...
                 '  - path: "examples"\n']);

            testCase.verifyError( ...
                @() mip.config.read_mip_yaml(testCase.TestDir), ...
                'mip:invalidMipYaml');
        end

        function testReadYamlWithBuilds(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "1.0.0"\nbuilds:\n  - architectures: [any]\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyFalse(isempty(cfg.builds));
        end

        function testReadYamlMissingName(testCase)
            writeYaml(testCase.TestDir, 'version: "1.0.0"\n');

            testCase.verifyError(@() mip.config.read_mip_yaml(testCase.TestDir), ...
                'mip:invalidMipYaml');
        end

        function testReadYamlRejectsNonCanonicalName(testCase)
            % mip.yaml's "name" field must be in canonical form (lowercase).
            writeYaml(testCase.TestDir, 'name: MyPkg\nversion: "1.0.0"\n');

            testCase.verifyError(@() mip.config.read_mip_yaml(testCase.TestDir), ...
                'mip:invalidMipYaml');
        end

        function testReadYamlMissingFile(testCase)
            emptyDir = fullfile(testCase.TestDir, 'empty');
            mkdir(emptyDir);
            testCase.verifyError(@() mip.config.read_mip_yaml(emptyDir), ...
                'mip:mipYamlNotFound');
        end

        function testReadYamlDefaultVersion(testCase)
            writeYaml(testCase.TestDir, 'name: mypkg\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.version, '');
        end

        function testReadYamlBlankVersion(testCase)
            writeYaml(testCase.TestDir, 'name: mypkg\nversion: ""\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.version, '');
        end

        function testReadYamlOptionalFields(testCase)
            writeYaml(testCase.TestDir, ...
                ['name: mypkg\nversion: "1.0.0"\n' ...
                 'description: "A test package"\n' ...
                 'license: MIT\n' ...
                 'homepage: "https://example.com"\n' ...
                 'repository: "https://github.com/test/repo"\n']);

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.description, 'A test package');
            testCase.verifyEqual(cfg.license, 'MIT');
            testCase.verifyEqual(cfg.homepage, 'https://example.com');
            testCase.verifyEqual(cfg.repository, 'https://github.com/test/repo');
        end

        function testReadYamlEmptyDependencies(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "1.0.0"\ndependencies: []\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.dependencies, {});
        end

        function testReadYamlUtf8NonAsciiDescription(testCase)
            % Regression: a non-ASCII description (em-dash, U+2014) must
            % round-trip as UTF-8 on every platform and MATLAB release.
            % read_mip_yaml must decode the bytes itself rather than rely on
            % the platform default, because fread('*char') ignores fopen's
            % encoding on some releases (R2023a on Windows defaults to
            % windows-1252), mangling the em-dash into mojibake ('â€"') and
            % breaking the scheduled-build metadata comparison.
            emDash = char(8212);  % U+2014 EM DASH
            content = ['name: mypkg' newline ...
                       'version: "1.0.0"' newline ...
                       'description: "A ' emDash ' B"' newline];
            % Write deterministic UTF-8 bytes, independent of the platform's
            % default file-write encoding.
            utf8Bytes = unicode2native(content, 'UTF-8');
            fid = fopen(fullfile(testCase.TestDir, 'mip.yaml'), 'w');
            fwrite(fid, utf8Bytes, 'uint8');
            fclose(fid);

            % Sanity-check that this content actually exercises the bug:
            % decoding the same bytes as windows-1252 (what the broken
            % Windows read did) must corrupt the single em-dash into the
            % three-character mojibake, so a correct decode is a real signal.
            mojibake = native2unicode(utf8Bytes, 'windows-1252');
            testCase.verifyTrue(contains(mojibake, ['A ' char([226 8364 8221]) ' B']), ...
                'test fixture should reproduce the windows-1252 mojibake');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.description, ['A ' emDash ' B']);
        end

    end
end

function writeYaml(dirPath, content)
    fid = fopen(fullfile(dirPath, 'mip.yaml'), 'w');
    fprintf(fid, content);
    fclose(fid);
end
