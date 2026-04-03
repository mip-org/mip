classdef TestReadMipYaml < matlab.unittest.TestCase
%TESTREADMIPYAML   Tests for mip.utils.read_mip_yaml.

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

            cfg = mip.utils.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.name, 'testpkg');
            testCase.verifyEqual(cfg.version, '1.0.0');
            testCase.verifyEqual(cfg.dependencies, {});
            testCase.verifyEqual(cfg.addpaths, {});
        end

        function testReadYamlWithDependencies(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "2.0.0"\ndependencies: [depA, depB]\n');

            cfg = mip.utils.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.name, 'mypkg');
            testCase.verifyEqual(sort(cfg.dependencies), sort({'depA', 'depB'}));
        end

        function testReadYamlWithAddpaths(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "1.0.0"\naddpaths:\n  - path: "."\n');

            cfg = mip.utils.read_mip_yaml(testCase.TestDir);
            testCase.verifyFalse(isempty(cfg.addpaths));
        end

        function testReadYamlWithBuilds(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "1.0.0"\nbuilds:\n  - architectures: [any]\n');

            cfg = mip.utils.read_mip_yaml(testCase.TestDir);
            testCase.verifyFalse(isempty(cfg.builds));
        end

        function testReadYamlMissingName(testCase)
            writeYaml(testCase.TestDir, 'version: "1.0.0"\n');

            testCase.verifyError(@() mip.utils.read_mip_yaml(testCase.TestDir), ...
                'mip:invalidMipYaml');
        end

        function testReadYamlMissingFile(testCase)
            emptyDir = fullfile(testCase.TestDir, 'empty');
            mkdir(emptyDir);
            testCase.verifyError(@() mip.utils.read_mip_yaml(emptyDir), ...
                'mip:mipYamlNotFound');
        end

        function testReadYamlDefaultVersion(testCase)
            writeYaml(testCase.TestDir, 'name: mypkg\n');

            cfg = mip.utils.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.version, 'unknown');
        end

        function testReadYamlOptionalFields(testCase)
            writeYaml(testCase.TestDir, ...
                ['name: mypkg\nversion: "1.0.0"\n' ...
                 'description: "A test package"\n' ...
                 'license: MIT\n' ...
                 'homepage: "https://example.com"\n' ...
                 'repository: "https://github.com/test/repo"\n']);

            cfg = mip.utils.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.description, 'A test package');
            testCase.verifyEqual(cfg.license, 'MIT');
            testCase.verifyEqual(cfg.homepage, 'https://example.com');
            testCase.verifyEqual(cfg.repository, 'https://github.com/test/repo');
        end

        function testReadYamlEmptyDependencies(testCase)
            writeYaml(testCase.TestDir, ...
                'name: mypkg\nversion: "1.0.0"\ndependencies: []\n');

            cfg = mip.utils.read_mip_yaml(testCase.TestDir);
            testCase.verifyEqual(cfg.dependencies, {});
        end

    end
end

function writeYaml(dirPath, content)
    fid = fopen(fullfile(dirPath, 'mip.yaml'), 'w');
    fprintf(fid, content);
    fclose(fid);
end
