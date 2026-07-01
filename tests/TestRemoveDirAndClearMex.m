classdef TestRemoveDirAndClearMex < matlab.unittest.TestCase
%TESTREMOVEDIRANDCLEARMEX   Tests for robust directory removal, the trash
% area, and MEX unloading.
%
% Covers mip.paths.remove_dir, mip.paths.get_trash_dir, mip.paths.purge_trash,
% and mip.build.clear_mex, plus the uninstall integration that funnels
% package-directory removal through them.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
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

        %% --- mip.paths.get_trash_dir ---

        function testTrashDirIsUnderRoot(testCase)
            testCase.verifyEqual(mip.paths.get_trash_dir(), ...
                fullfile(testCase.TestRoot, '.trash'));
        end

        %% --- mip.paths.remove_dir ---

        function testRemoveDirDeletesDirectory(testCase)
            target = fullfile(testCase.TestRoot, 'packages', 'victim');
            mkdir(target);
            fid = fopen(fullfile(target, 'a.txt'), 'w'); fwrite(fid, 'x'); fclose(fid);

            mip.paths.remove_dir(target);

            testCase.verifyFalse(exist(target, 'dir') > 0, ...
                'remove_dir should delete the target directory');
            % A deletable directory leaves nothing behind in the trash.
            testCase.verifyTrue(isTrashEmpty(testCase.TestRoot), ...
                'Trash should be empty after a successful removal');
        end

        function testRemoveDirMissingIsNoOp(testCase)
            missing = fullfile(testCase.TestRoot, 'packages', 'does_not_exist');
            % Must not error.
            mip.paths.remove_dir(missing);
            testCase.verifyFalse(exist(missing, 'dir') > 0);
        end

        function testRemoveDirCreatesTrashOnDemand(testCase)
            trashDir = mip.paths.get_trash_dir();
            testCase.verifyFalse(exist(trashDir, 'dir') > 0, ...
                'Trash should not exist before any removal');

            target = fullfile(testCase.TestRoot, 'packages', 'victim');
            mkdir(target);
            mip.paths.remove_dir(target);

            testCase.verifyTrue(exist(trashDir, 'dir') > 0, ...
                'remove_dir should create the trash directory');
        end

        %% --- mip.paths.purge_trash ---

        function testPurgeTrashRemovesLeftoverDirs(testCase)
            trashDir = mip.paths.get_trash_dir();
            mkdir(trashDir);
            leftover1 = fullfile(trashDir, 'leftover1');
            leftover2 = fullfile(trashDir, 'leftover2');
            mkdir(leftover1);
            mkdir(leftover2);
            fid = fopen(fullfile(leftover1, 'b.txt'), 'w'); fwrite(fid, 'y'); fclose(fid);

            mip.paths.purge_trash();

            testCase.verifyTrue(isTrashEmpty(testCase.TestRoot), ...
                'purge_trash should remove all leftover entries');
        end

        function testPurgeTrashNoTrashIsNoOp(testCase)
            % Must not error when the trash directory does not exist.
            testCase.verifyFalse(exist(mip.paths.get_trash_dir(), 'dir') > 0);
            mip.paths.purge_trash();
        end

        %% --- mip.build.clear_mex ---

        function testClearMexFindsMexFilesRecursively(testCase)
            base = fullfile(testCase.TestRoot, 'pkgsrc');
            mkdir(base);
            mkdir(fullfile(base, 'sub'));
            writeFile(fullfile(base, 'a.mexa64'));
            writeFile(fullfile(base, 'sub', 'b.mexw64'));
            writeFile(fullfile(base, 'sub', 'c.mexmaca64'));
            writeFile(fullfile(base, 'notmex.m'));
            writeFile(fullfile(base, 'readme.txt'));

            cleared = mip.build.clear_mex(base);

            expected = sort({ ...
                fullfile(base, 'a.mexa64'), ...
                fullfile(base, 'sub', 'b.mexw64'), ...
                fullfile(base, 'sub', 'c.mexmaca64')});
            testCase.verifyEqual(sort(cleared(:)'), expected, ...
                'clear_mex should report exactly the MEX files (any arch), recursively');
        end

        function testClearMexNoMexReturnsEmpty(testCase)
            base = fullfile(testCase.TestRoot, 'puresrc');
            mkdir(base);
            writeFile(fullfile(base, 'only.m'));

            cleared = mip.build.clear_mex(base);
            testCase.verifyEmpty(cleared);
        end

        function testClearMexMissingDirReturnsEmpty(testCase)
            cleared = mip.build.clear_mex(fullfile(testCase.TestRoot, 'nope'));
            testCase.verifyEmpty(cleared);
            cleared = mip.build.clear_mex('');
            testCase.verifyEmpty(cleared);
        end

        %% --- integration: uninstall removes the package dir via the trash ---

        function testUninstallRemovesPackageDirAndLeavesTrashEmpty(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'withmex');
            % Drop a (fake) MEX in the package source dir to exercise the
            % clear-on-unload path. It is not a real binary, so it is not
            % actually locked and the directory deletes cleanly.
            writeFile(fullfile(pkgDir, 'withmex', ['fake.' mexext]));
            mip.state.add_directly_installed('mip-org/core/withmex');
            mip.load('mip-org/core/withmex');

            mip.uninstall('mip-org/core/withmex');

            testCase.verifyFalse(exist(pkgDir, 'dir') > 0, ...
                'Package directory should be removed');
            testCase.verifyTrue(isTrashEmpty(testCase.TestRoot), ...
                'Trash should be empty after uninstalling a deletable package');
            testCase.verifyFalse(ismember('gh/mip-org/core/withmex', ...
                mip.state.get_directly_installed()));
        end

    end
end

function writeFile(p)
    fid = fopen(p, 'w');
    fwrite(fid, 'x');
    fclose(fid);
end

function tf = isTrashEmpty(root)
    trashDir = fullfile(root, '.trash');
    if ~exist(trashDir, 'dir')
        tf = true;
        return
    end
    entries = dir(trashDir);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    tf = isempty(entries);
end
