classdef TestProjectAddRemove < matlab.unittest.TestCase
%TESTPROJECTADDREMOVE   Tests for "mip project add" / "mip project remove":
%   spec editing, group flags, re-locking, rollback on lock failure, and
%   the sync/prune step.

    properties
        OrigMipRoot
        TestRoot
        WorkDir
        SourceDir
        BundleDir
        OrigPwd
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_proj_ar_root'];
            testCase.WorkDir = [tempname '_mip_proj_ar_work'];
            testCase.SourceDir = [tempname '_mip_proj_ar_src'];
            testCase.BundleDir = [tempname '_mip_proj_ar_bundle'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            mkdir(testCase.SourceDir);
            mkdir(testCase.BundleDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.OrigPwd = pwd;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigPwd);
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            dirs = {testCase.TestRoot, testCase.WorkDir, ...
                    testCase.SourceDir, testCase.BundleDir};
            for d = dirs
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        function testAddDeclaresLocksAndSyncs(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: []'});
            cd(testCase.WorkDir);

            evalc('mip.project.add(''pkga'')');

            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga'});
            testCase.verifyTrue(isfile(fullfile(testCase.WorkDir, 'mip.lock')), ...
                'add must enter uv mode by creating the lock');
            testCase.verifyTrue(envHasPackage(testCase, 'pkga'), ...
                'add must sync the environment');
        end

        function testAddDevGroup(testCase)
            indexWithBundles(testCase, {'pkgtest'});
            writeSpec(testCase, {'dependencies: []'});
            cd(testCase.WorkDir);

            evalc('mip.project.add(''--dev'', ''pkgtest'')');

            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEmpty(spec.dependencies);
            testCase.verifyEqual(spec.dependency_groups.dev, {'pkgtest'});
            testCase.verifyTrue(envHasPackage(testCase, 'pkgtest'), ...
                'the dev group installs by default on sync');
        end

        function testAddNoSync(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: []'});
            cd(testCase.WorkDir);

            evalc('mip.project.add(''--no-sync'', ''pkga'')');

            testCase.verifyTrue(isfile(fullfile(testCase.WorkDir, 'mip.lock')));
            testCase.verifyFalse(isfolder(fullfile(testCase.WorkDir, '.mip')), ...
                '--no-sync must not touch the environment');
        end

        function testAddRollsBackSpecOnLockFailure(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            original = fileread(fullfile(testCase.WorkDir, 'mip.yaml'));

            testCase.verifyError(@() evalc('mip.project.add(''nosuchpkg'')'), ...
                'mip:packageNotFound');
            testCase.verifyEqual(fileread(fullfile(testCase.WorkDir, 'mip.yaml')), ...
                original, 'a failed lock must roll back the spec edit');
        end

        function testAddRejectsNonChannelAndConflictingFlags(testCase)
            writeSpec(testCase, {'dependencies: []'});
            cd(testCase.WorkDir);
            testCase.verifyError(@() evalc('mip.project.add(''local/mypkg'')'), ...
                'mip:project:unsupportedDependency');
            testCase.verifyError(...
                @() evalc('mip.project.add(''--dev'', ''--group'', ''docs'', ''pkga'')'), ...
                'mip:project:conflictingFlags');
            testCase.verifyError(...
                @() evalc('mip.project.add(''--group'', ''bad-name'', ''pkga'')'), ...
                'mip:project:invalidGroupName');
        end

        function testRemovePrunesOnSync(testCase)
            indexWithBundles(testCase, {'pkga', 'pkgb'});
            writeSpec(testCase, {'dependencies: [pkga, pkgb]'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');
            evalc('mip.project.sync()');
            testCase.verifyTrue(envHasPackage(testCase, 'pkgb'));

            evalc('mip.project.remove(''pkgb'')');

            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga'});
            testCase.verifyFalse(envHasPackage(testCase, 'pkgb'), ...
                'remove must prune the package on sync');
            testCase.verifyTrue(envHasPackage(testCase, 'pkga'));
        end

        function testRemoveNotDeclaredErrors(testCase)
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            testCase.verifyError(@() evalc('mip.project.remove(''pkgb'')'), ...
                'mip:project:dependencyNotDeclared');
        end

        function testAddUpdatesExistingPin(testCase)
            % Two published versions; the spec pins 1.0.0, then add
            % re-pins to 2.0.0 in place.
            [urlA1, ~] = bundlePackage(testCase, 'pkga', '1.0.0');
            [urlA2, ~] = bundlePackage(testCase, 'pkga', '2.0.0');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'version', '1.0.0', 'mhl_url', urlA1), ...
                struct('name', 'pkga', 'version', '2.0.0', 'mhl_url', urlA2)});
            writeSpec(testCase, {'dependencies: [pkga@1.0.0]'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');
            evalc('mip.project.sync()');

            evalc('mip.project.add(''pkga@2.0.0'')');

            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.dependencies, {'pkga@2.0.0'});
            lockData = mip.project.read_lock(fullfile(testCase.WorkDir, 'mip.lock'));
            testCase.verifyEqual(lockData.packages{1}.version, '2.0.0');
            info = jsondecode(fileread(fullfile(testCase.WorkDir, '.mip', ...
                'packages', 'gh', 'mip-org', 'core', 'pkga', 'mip.json')));
            testCase.verifyEqual(info.version, '2.0.0', ...
                'sync must replace the installed version to match the lock');
        end

    end
end

function indexWithBundles(testCase, names)
% Bundle each named package and publish a fake core index for them.
    entries = cell(1, numel(names));
    for i = 1:numel(names)
        [mhlUrl, sha] = bundlePackage(testCase, names{i}, '1.0.0');
        entries{i} = struct('name', names{i}, 'version', '1.0.0', ...
                            'mhl_url', mhlUrl, 'mhl_sha256', sha);
    end
    writeChannelIndex(testCase.TestRoot, 'mip-org/core', entries);
end

function [mhlUrl, sha] = bundlePackage(testCase, pkgName, version)
    srcParent = fullfile(testCase.SourceDir, [pkgName '_' strrep(version, '.', '_')]);
    mkdir(srcParent);
    srcDir = createTestSourcePackage(srcParent, pkgName, 'version', version); %#ok<NASGU> (used inside evalc)
    outDir = fullfile(testCase.BundleDir, [pkgName '_' strrep(version, '.', '_')]);
    mkdir(outDir);
    evalc('mip.bundle(srcDir, ''--output'', outDir, ''--arch'', ''any'')');
    mhlFiles = dir(fullfile(outDir, [pkgName '-*.mhl']));
    testCase.assertNotEmpty(mhlFiles, '.mhl bundle was not produced');
    mhlUrl = fullfile(outDir, mhlFiles(1).name);
    sha = mip.channel.sha256(mhlUrl);
end

function tf = envHasPackage(testCase, name)
    tf = isfolder(fullfile(testCase.WorkDir, '.mip', 'packages', ...
                           'gh', 'mip-org', 'core', name));
end

function writeSpec(testCase, lines)
    fid = fopen(fullfile(testCase.WorkDir, 'mip.yaml'), 'w');
    fwrite(fid, [strjoin(lines, newline) newline]);
    fclose(fid);
end
