classdef TestOpsBackupRestore < matlab.unittest.TestCase
%TESTOPSBACKUPRESTORE   Tests for the mip.ops transactional primitives:
%   backup_package / restore_backups / discard_backups, and the
%   snapshot_loaded / reload_missing pair.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_ops_backup_test'];
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

        %% --- backup_package ---

        function testBackup_MovesDirAndClearsDirectStatus(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'bpkg');
            mip.state.add_directly_installed('mip-org/core/bpkg');

            backup = mip.ops.backup_package('gh/mip-org/core/bpkg');

            testCase.verifyFalse(exist(pkgDir, 'dir') > 0, ...
                'Package dir should be moved away by backup');
            testCase.verifyTrue(exist(backup.backupDir, 'dir') > 0, ...
                'Backup dir should exist');
            testCase.verifyTrue(backup.wasDirectlyInstalled);
            testCase.verifyFalse(ismember('gh/mip-org/core/bpkg', ...
                mip.state.get_directly_installed()), ...
                'Directly-installed status should be cleared during backup');

            mip.ops.restore_backups(backup);
        end

        function testBackup_RecordsNotDirectlyInstalled(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'tpkg');

            backup = mip.ops.backup_package('gh/mip-org/core/tpkg');
            testCase.verifyFalse(backup.wasDirectlyInstalled);

            mip.ops.restore_backups(backup);
            testCase.verifyFalse(ismember('gh/mip-org/core/tpkg', ...
                mip.state.get_directly_installed()), ...
                'Restore must not invent directly-installed status');
        end

        %% --- restore_backups ---

        function testRestore_RestoresDirAndDirectStatus(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'rpkg');
            mip.state.add_directly_installed('mip-org/core/rpkg');

            backup = mip.ops.backup_package('gh/mip-org/core/rpkg');
            mip.ops.restore_backups(backup);

            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Package dir should be restored');
            testCase.verifyTrue(isfile(fullfile(pkgDir, 'mip.json')), ...
                'Restored dir should have its original contents');
            testCase.verifyTrue(ismember('gh/mip-org/core/rpkg', ...
                mip.state.get_directly_installed()), ...
                'Directly-installed status should be restored');
        end

        function testRestore_RemovesPartialReplacement(testCase)
            % If a failed replacement left a partial package dir behind,
            % restore must clear it before moving the backup into place.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'ppkg');
            backup = mip.ops.backup_package('gh/mip-org/core/ppkg');

            mkdir(pkgDir);
            fid = fopen(fullfile(pkgDir, 'partial.txt'), 'w');
            fwrite(fid, 'partial');
            fclose(fid);

            mip.ops.restore_backups(backup);

            testCase.verifyTrue(isfile(fullfile(pkgDir, 'mip.json')), ...
                'Original contents should be back in place');
            testCase.verifyFalse(isfile(fullfile(pkgDir, 'partial.txt')), ...
                'Partial replacement contents should be gone');
        end

        function testRestore_RecreatesMissingParentDir(testCase)
            % update.m removes empty source-type parents after backing up a
            % local package; restore must recreate them.
            pkgDir = createTestPackage(testCase.TestRoot, '', '', 'lpkg', 'type', 'local');
            backup = mip.ops.backup_package('local/lpkg');
            parentDir = fileparts(pkgDir);
            if exist(parentDir, 'dir')
                rmdir(parentDir, 's');
            end

            mip.ops.restore_backups(backup);

            testCase.verifyTrue(exist(pkgDir, 'dir') > 0, ...
                'Restore should recreate the missing parent directory');
        end

        %% --- discard_backups ---

        function testDiscard_RemovesBackupDir(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'dpkg');
            backup = mip.ops.backup_package('gh/mip-org/core/dpkg');

            mip.ops.discard_backups(backup);

            testCase.verifyFalse(exist(backup.backupDir, 'dir') > 0, ...
                'Backup dir should be removed on discard');
        end

        function testBackupTrio_SupportsStructArrays(testCase)
            dirA = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'arra');
            dirB = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'arrb');
            mip.state.add_directly_installed('mip-org/core/arra');

            backups = mip.ops.backup_package('gh/mip-org/core/arra');
            backups(end+1) = mip.ops.backup_package('gh/mip-org/core/arrb');

            mip.ops.restore_backups(backups);
            testCase.verifyTrue(exist(dirA, 'dir') > 0);
            testCase.verifyTrue(exist(dirB, 'dir') > 0);
            testCase.verifyTrue(ismember('gh/mip-org/core/arra', ...
                mip.state.get_directly_installed()));
        end

        %% --- snapshot_loaded / reload_missing ---

        function testSnapshotReload_ReloadsUnloadedPackage(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'snappkg');
            mip.load('mip-org/core/snappkg');

            snapshot = mip.ops.snapshot_loaded();
            mip.unload('mip-org/core/snappkg');
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/snappkg'));

            mip.ops.reload_missing(snapshot);

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/snappkg'), ...
                'Package should be reloaded from the snapshot');
            testCase.verifyTrue(mip.state.is_directly_loaded('gh/mip-org/core/snappkg'), ...
                'Directly-loaded status should survive the reload');
        end

        function testSnapshotReload_PreservesTransitiveDistinction(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depa');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depa'});
            mip.load('mip-org/core/mainpkg');
            testCase.assertTrue(mip.state.is_loaded('gh/mip-org/core/depa'));
            testCase.assertFalse(mip.state.is_directly_loaded('gh/mip-org/core/depa'));

            snapshot = mip.ops.snapshot_loaded();
            mip.unload('mip-org/core/mainpkg');
            mip.unload('mip-org/core/depa');

            mip.ops.reload_missing(snapshot);

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/mainpkg'));
            testCase.verifyTrue(mip.state.is_directly_loaded('gh/mip-org/core/mainpkg'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/depa'));
            testCase.verifyFalse(mip.state.is_directly_loaded('gh/mip-org/core/depa'), ...
                'Transitive dep must not be promoted to directly loaded by the reload');
        end

        function testReloadMissing_SkipsUninstalledPackage(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'gonepkg');
            mip.load('mip-org/core/gonepkg');
            snapshot = mip.ops.snapshot_loaded();
            mip.unload('mip-org/core/gonepkg');
            mip.uninstall('mip-org/core/gonepkg');

            % Must not error; the uninstalled package is skipped.
            mip.ops.reload_missing(snapshot);
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/gonepkg'));
        end

    end
end
