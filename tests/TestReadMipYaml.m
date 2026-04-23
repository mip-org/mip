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

        function testReadYamlMissingFile(testCase)
            emptyDir = fullfile(testCase.TestDir, 'empty');
            mkdir(emptyDir);
            testCase.verifyError(@() mip.config.read_mip_yaml(emptyDir), ...
                'mip:mipYamlNotFound');
        end

        function testReadYamlDefaultVersion(testCase)
            writeYaml(testCase.TestDir, 'name: mypkg\n');

            cfg = mip.config.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.version, 'unknown');
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

    end
end

function writeYaml(dirPath, content)
    fid = fopen(fullfile(dirPath, 'mip.yaml'), 'w');
    fprintf(fid, content);
    fclose(fid);
end
