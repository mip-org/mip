classdef TestProjectSpec < matlab.unittest.TestCase
%TESTPROJECTSPEC   Tests for the project-spec plumbing: read_spec (optional
%   identity, dependency_groups, channels), project discovery (find_dir /
%   locate), the mip.yaml list editor (edit_spec), and lock round-tripping.

    properties
        OrigMipRoot
        TestRoot
        WorkDir
        OrigPwd
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_proj_spec_root'];
            testCase.WorkDir = [tempname '_mip_proj_spec_work'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.OrigPwd = pwd;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigPwd);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            for d = {testCase.TestRoot, testCase.WorkDir}
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        % ---- read_spec ----

        function testReadSpecNameless(testCase)
            writeSpec(testCase, { ...
                'dependencies:', ...
                '  - pkga', ...
                '  - pkgb@1.2.0'});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.name, '');
            testCase.verifyEqual(spec.version, '');
            testCase.verifyEqual(spec.dependencies, {'pkga', 'pkgb@1.2.0'});
            testCase.verifyEmpty(fieldnames(spec.dependency_groups));
            testCase.verifyEmpty(spec.channels);
        end

        function testReadSpecGroupsAndChannels(testCase)
            writeSpec(testCase, { ...
                'name: myproj', ...
                'version: "2.0.0"', ...
                'dependencies: [pkga]', ...
                'dependency_groups:', ...
                '  dev:', ...
                '    - pkgtest', ...
                '  docs:', ...
                '    - pkgdocs', ...
                'channels:', ...
                '  - mylab/custom'});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.name, 'myproj');
            testCase.verifyEqual(spec.version, '2.0.0');
            testCase.verifyEqual(spec.dependencies, {'pkga'});
            testCase.verifyEqual(fieldnames(spec.dependency_groups), {'dev'; 'docs'});
            testCase.verifyEqual(spec.dependency_groups.dev, {'pkgtest'});
            testCase.verifyEqual(spec.channels, {'mylab/custom'});
        end

        function testReadSpecInvalidNameErrors(testCase)
            writeSpec(testCase, {'name: Bad.Name'});
            testCase.verifyError(...
                @() mip.project.read_spec(testCase.WorkDir), ...
                'mip:invalidMipYaml');
        end

        function testReadSpecInvalidGroupsErrors(testCase)
            writeSpec(testCase, {'dependency_groups: [dev]'});
            testCase.verifyError(...
                @() mip.project.read_spec(testCase.WorkDir), ...
                'mip:invalidMipYaml');
        end

        function testReadSpecMissingFileErrors(testCase)
            testCase.verifyError(...
                @() mip.project.read_spec(fullfile(testCase.WorkDir, 'nope')), ...
                'mip:project:specNotFound');
        end

        % ---- project discovery ----

        function testFindDirWalksUp(testCase)
            writeSpec(testCase, {'dependencies: []'});
            nested = fullfile(testCase.WorkDir, 'sub', 'subsub');
            mkdir(nested);
            testCase.verifyEqual(mip.project.find_dir(nested), testCase.WorkDir);
        end

        function testFindDirInnermostWins(testCase)
            writeSpec(testCase, {'dependencies: []'});
            inner = fullfile(testCase.WorkDir, 'inner');
            mkdir(inner);
            writeFile(fullfile(inner, 'mip.yaml'), {'dependencies: []'});
            testCase.verifyEqual(mip.project.find_dir(inner), inner);
        end

        function testLocateAnnouncesAndErrors(testCase)
            writeSpec(testCase, {'dependencies: []'});
            cd(testCase.WorkDir);
            output = evalc('mip.project.locate()');
            testCase.verifyTrue(contains(output, 'using project at'));

            empty = [tempname '_no_proj'];
            mkdir(empty);
            cleanup = onCleanup(@() rmdir(empty, 's')); %#ok<NASGU>
            testCase.verifyError(@() mip.project.locate(empty), ...
                'mip:project:notFound');
        end

        function testLocateDirectoryOverride(testCase)
            writeSpec(testCase, {'dependencies: []'});
            proj = [];
            evalc('proj = mip.project.locate(testCase.WorkDir);');
            testCase.verifyEqual(proj.dir, testCase.WorkDir);
            testCase.verifyEqual(proj.spec_path, fullfile(testCase.WorkDir, 'mip.yaml'));
            testCase.verifyEqual(proj.env_path, fullfile(testCase.WorkDir, '.mip'));
        end

        % ---- edit_spec ----

        function testEditSpecAddToBlockList(testCase)
            writeSpec(testCase, { ...
                '# header comment', ...
                'dependencies:', ...
                '  - pkga', ...
                'description: "x"'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, '', {'pkgb@2.0'}, {});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga', 'pkgb@2.0'});
            text = fileread(specPath);
            testCase.verifyTrue(contains(text, '# header comment'), ...
                'comments outside the list must be preserved');
            testCase.verifyTrue(contains(text, 'description: "x"'));
        end

        function testEditSpecAddReplacesSameName(testCase)
            writeSpec(testCase, {'dependencies:', '  - pkga@1.0'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, '', {'pkga@2.0'}, {});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga@2.0'});
        end

        function testEditSpecFlowList(testCase)
            writeSpec(testCase, {'dependencies: [pkga, pkgb]'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, '', {'pkgc'}, {'pkga'});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkgb', 'pkgc'});
        end

        function testEditSpecEmptyFlowList(testCase)
            writeSpec(testCase, {'dependencies: []'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, '', {'pkga'}, {});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga'});
        end

        function testEditSpecMissingKeyAppends(testCase)
            writeSpec(testCase, {'name: myproj'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, '', {'pkga'}, {});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga'});
            testCase.verifyEqual(spec.name, 'myproj');
        end

        function testEditSpecGroupCreation(testCase)
            writeSpec(testCase, {'dependencies: [pkga]'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, 'dev', {'pkgtest'}, {});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependency_groups.dev, {'pkgtest'});
            % Add a second group under the now-existing parent.
            mip.project.edit_spec(specPath, 'docs', {'pkgdocs'}, {});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependency_groups.dev, {'pkgtest'});
            testCase.verifyEqual(spec.dependency_groups.docs, {'pkgdocs'});
            testCase.verifyEqual(spec.dependencies, {'pkga'});
        end

        function testEditSpecRemove(testCase)
            writeSpec(testCase, { ...
                'dependencies:', ...
                '  - pkga', ...
                '  - pkgb  # keep an eye on this one', ...
                '  - pkgc'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, '', {}, {'pkgb'});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga', 'pkgc'});
        end

        function testEditSpecRemoveIgnoresVersionAndCase(testCase)
            writeSpec(testCase, {'dependencies:', '  - Pkg_A@1.0'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            mip.project.edit_spec(specPath, '', {}, {'pkg-a'});
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEmpty(spec.dependencies);
        end

        function testEditSpecRemoveNotDeclaredErrors(testCase)
            writeSpec(testCase, {'dependencies: [pkga]'});
            specPath = fullfile(testCase.WorkDir, 'mip.yaml');
            testCase.verifyError(...
                @() mip.project.edit_spec(specPath, '', {}, {'nope'}), ...
                'mip:project:dependencyNotDeclared');
        end

        % ---- lock read/write round trip ----

        function testLockRoundTrip(testCase)
            lockPath = fullfile(testCase.WorkDir, 'mip.lock');
            entry = struct('fqn', 'gh/mip-org/core/pkga', 'name', 'pkga', ...
                'version', '1.0.0', 'architecture', 'any', ...
                'mhl_url', 'https://x.test/pkga.mhl', 'mhl_sha256', 'abc', ...
                'commit_hash', '', 'source_hash', '', ...
                'dependencies', {{'pkgb'}}, 'direct', true, 'base', true, ...
                'groups', {{'dev'}});
            lockData = struct('lock_version', 1, 'mip_version', mip.version(), ...
                'spec_sha256', 'ffff', 'packages', {{entry}});
            mip.project.write_lock(lockPath, lockData);

            back = mip.project.read_lock(lockPath);
            testCase.verifyEqual(back.lock_version, 1);
            testCase.verifyEqual(back.spec_sha256, 'ffff');
            testCase.verifyEqual(numel(back.packages), 1);
            p = back.packages{1};
            testCase.verifyEqual(p.fqn, 'gh/mip-org/core/pkga');
            testCase.verifyEqual(p.dependencies, {'pkgb'});
            testCase.verifyEqual(p.groups, {'dev'});
            testCase.verifyTrue(p.direct);
            testCase.verifyTrue(p.base);
        end

        function testReadLockMissingAndInvalid(testCase)
            testCase.verifyError(...
                @() mip.project.read_lock(fullfile(testCase.WorkDir, 'mip.lock')), ...
                'mip:project:lockNotFound');
            lockPath = fullfile(testCase.WorkDir, 'mip.lock');
            writeFile(lockPath, {'{"lock_version": 99, "packages": []}'});
            testCase.verifyError(@() mip.project.read_lock(lockPath), ...
                'mip:project:lockInvalid');
        end

    end
end

function writeSpec(testCase, lines)
    writeFile(fullfile(testCase.WorkDir, 'mip.yaml'), lines);
end

function writeFile(p, lines)
    fid = fopen(p, 'w');
    fwrite(fid, [strjoin(lines, newline) newline]);
    fclose(fid);
end
