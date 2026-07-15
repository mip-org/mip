classdef TestProjectSync < matlab.unittest.TestCase
%TESTPROJECTSYNC   Tests for "mip project sync": installing from the lock,
%   group selection, pruning with first-sync confirmation, the digest
%   check, project self-install, and the sync stamp.

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
        WorkDir
        SourceDir
        BundleDir
        OrigPwd
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_proj_sync_root'];
            testCase.WorkDir = [tempname '_mip_proj_sync_work'];
            testCase.SourceDir = [tempname '_mip_proj_sync_src'];
            testCase.BundleDir = [tempname '_mip_proj_sync_bundle'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            mkdir(testCase.SourceDir);
            mkdir(testCase.BundleDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            setenv('MIP_CONFIRM', '');
            testCase.OrigPwd = pwd;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigPwd);
            cleanupTestPaths(testCase.TestRoot);
            if isfolder(fullfile(testCase.WorkDir, '.mip'))
                cleanupTestPaths(fullfile(testCase.WorkDir, '.mip'));
            end
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            setenv('MIP_CONFIRM', testCase.OrigMipConfirm);
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

        function testSyncInstallsFromLock(testCase)
            [urlA, shaA] = bundlePackage(testCase, 'pkga');
            [urlB, ~] = bundlePackage(testCase, 'pkgb');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'mhl_url', urlA, 'mhl_sha256', shaA), ...
                struct('name', 'pkgb', 'mhl_url', urlB)});
            writeSpec(testCase, { ...
                'dependencies: [pkga]', ...
                'dependency_groups:', ...
                '  dev:', ...
                '    - pkgb'});
            lockAndSync(testCase);

            envPath = fullfile(testCase.WorkDir, '.mip');
            testCase.verifyTrue(mip.env.is_env(envPath), ...
                'sync must materialize the environment, marker and all');
            testCase.verifyTrue(isfolder(fullfile(envPath, 'packages', ...
                'gh', 'mip-org', 'core', 'pkga')));
            testCase.verifyTrue(isfolder(fullfile(envPath, 'packages', ...
                'gh', 'mip-org', 'core', 'pkgb')), ...
                'the dev group installs by default');
            testCase.verifyTrue(isfile(fullfile(envPath, 'mip-sync.json')), ...
                'sync must stamp the environment');

            % The direct flag is reconciled into the env's install state.
            direct = envDirectlyInstalled(testCase);
            testCase.verifyTrue(ismember('gh/mip-org/core/pkga', direct));
            testCase.verifyTrue(ismember('gh/mip-org/core/pkgb', direct));

            % MIP_ROOT is restored after sync.
            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot);
        end

        function testSyncGroupSelection(testCase)
            [urlA, ~] = bundlePackage(testCase, 'pkga');
            [urlB, ~] = bundlePackage(testCase, 'pkgb');
            [urlC, ~] = bundlePackage(testCase, 'pkgc');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'mhl_url', urlA), ...
                struct('name', 'pkgb', 'mhl_url', urlB), ...
                struct('name', 'pkgc', 'mhl_url', urlC)});
            writeSpec(testCase, { ...
                'dependencies: [pkga]', ...
                'dependency_groups:', ...
                '  dev:', ...
                '    - pkgb', ...
                '  docs:', ...
                '    - pkgc'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');

            evalc('mip.project.sync(''--no-dev'')');
            testCase.verifyTrue(envHasPackage(testCase, 'pkga'));
            testCase.verifyFalse(envHasPackage(testCase, 'pkgb'), ...
                '--no-dev must not install the dev group');
            testCase.verifyFalse(envHasPackage(testCase, 'pkgc'));

            evalc('mip.project.sync(''--all-groups'')');
            testCase.verifyTrue(envHasPackage(testCase, 'pkgb'));
            testCase.verifyTrue(envHasPackage(testCase, 'pkgc'));

            % A plain sync then prunes the group packages not selected.
            evalc('mip.project.sync(''--no-dev'')');
            testCase.verifyFalse(envHasPackage(testCase, 'pkgb'));
            testCase.verifyFalse(envHasPackage(testCase, 'pkgc'));

            testCase.verifyError(@() evalc('mip.project.sync(''--group'', ''nope'')'), ...
                'mip:project:unknownGroup');
        end

        function testSyncErrorsWithoutLock(testCase)
            writeSpec(testCase, {'dependencies: []'});
            cd(testCase.WorkDir);
            testCase.verifyError(@() evalc('mip.project.sync()'), ...
                'mip:project:lockNotFound');
        end

        function testFirstSyncPruneConfirms(testCase)
            [urlA, ~] = bundlePackage(testCase, 'pkga');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'mhl_url', urlA)});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');

            % A formerly hand-managed env: created by hand, one package
            % installed by hand, no sync stamp.
            envPath = fullfile(testCase.WorkDir, '.mip');
            mip.env.materialize(envPath);
            createTestPackage(envPath, 'mip-org', 'core', 'oldpkg');

            % Declined -> abort untouched.
            setenv('MIP_CONFIRM', 'n');
            testCase.verifyError(@() evalc('mip.project.sync()'), ...
                'mip:project:syncAborted');
            testCase.verifyTrue(envHasPackage(testCase, 'oldpkg'));

            % Confirmed -> pruned and synced.
            setenv('MIP_CONFIRM', 'y');
            evalc('mip.project.sync()');
            testCase.verifyFalse(envHasPackage(testCase, 'oldpkg'));
            testCase.verifyTrue(envHasPackage(testCase, 'pkga'));

            % A later sync prunes without confirmation (stamp present).
            setenv('MIP_CONFIRM', 'n');
            createTestPackage(envPath, 'mip-org', 'core', 'strayp');
            evalc('mip.project.sync()');
            testCase.verifyFalse(envHasPackage(testCase, 'strayp'), ...
                'a stamped env prunes unrecorded packages without confirmation');
        end

        function testSyncVerifiesLockedDigest(testCase)
            [urlA, ~] = bundlePackage(testCase, 'pkga');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'mhl_url', urlA, ...
                       'mhl_sha256', repmat('0', 1, 64))});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');
            if isempty(mip.channel.sha256(fullfile(testCase.WorkDir, 'mip.yaml')))
                testCase.assumeFail('JVM unavailable; digest check cannot run');
            end
            testCase.verifyError(@() evalc('mip.project.sync()'), ...
                'mip:digestMismatch');
            testCase.verifyFalse(envHasPackage(testCase, 'pkga'));
        end

        function testSyncInstallsNamedProjectEditable(testCase)
            [urlA, ~] = bundlePackage(testCase, 'pkga');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'mhl_url', urlA)});
            writeSpec(testCase, { ...
                'name: myproj', ...
                'version: "1.0.0"', ...
                'dependencies: [pkga]', ...
                'dependency_groups:', ...
                '  dev:', ...
                '    - pkga', ...
                'channels:', ...
                '  - mip-org/core', ...
                'paths:', ...
                '  - path: "."'});
            lockAndSync(testCase);

            envPath = fullfile(testCase.WorkDir, '.mip');
            projPkgDir = fullfile(envPath, 'packages', 'local', 'myproj');
            testCase.verifyTrue(isfolder(projPkgDir), ...
                'a named spec is installed into the env as the project package');
            info = jsondecode(fileread(fullfile(projPkgDir, 'mip.json')));
            testCase.verifyTrue(info.editable, ...
                'the project package must be an editable install');
            testCase.verifyFalse(isfield(info, 'dependency_groups'), ...
                'dependency_groups must be stripped from mip.json');
            testCase.verifyFalse(isfield(info, 'channels'), ...
                'channels must be stripped from mip.json');

            % Re-sync must not prune the project package.
            cd(testCase.WorkDir);
            evalc('mip.project.sync()');
            testCase.verifyTrue(isfolder(projPkgDir));
        end

    end
end

function [mhlUrl, sha] = bundlePackage(testCase, pkgName)
% Build a real .mhl for pkgName and return its local path (download_mhl
% accepts local paths wherever a URL is expected) and SHA-256 ('' when
% the JVM is unavailable).
    srcDir = createTestSourcePackage(testCase.SourceDir, pkgName); %#ok<NASGU> (used inside evalc)
    evalc('mip.bundle(srcDir, ''--output'', testCase.BundleDir, ''--arch'', ''any'')');
    mhlFiles = dir(fullfile(testCase.BundleDir, [pkgName '-*.mhl']));
    testCase.assertNotEmpty(mhlFiles, '.mhl bundle was not produced');
    mhlUrl = fullfile(testCase.BundleDir, mhlFiles(1).name);
    sha = mip.channel.sha256(mhlUrl);
end

function lockAndSync(testCase)
    cd(testCase.WorkDir);
    evalc('mip.project.lock()');
    evalc('mip.project.sync()');
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

function direct = envDirectlyInstalled(testCase)
% Read the env's directly-installed list with MIP_ROOT pointed at it.
    prior = getenv('MIP_ROOT');
    restore = onCleanup(@() setenv('MIP_ROOT', prior)); %#ok<NASGU>
    setenv('MIP_ROOT', fullfile(testCase.WorkDir, '.mip'));
    direct = mip.state.get_directly_installed();
end
