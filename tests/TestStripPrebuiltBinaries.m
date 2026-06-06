classdef TestStripPrebuiltBinaries < matlab.unittest.TestCase
%TESTSTRIPPREBUILTBINARIES   Tests for mip.build.strip_prebuilt_binaries.
%
% The function deletes vendored/stale compiled artifacts from a package
% tree before the channel builds its own from source. These tests verify
% that every binary kind is removed (recursively), that the .obj geometry
% exception is honored, and that source/data files survive.

    properties
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.TestRoot = [tempname '_strip_test'];
            mkdir(testCase.TestRoot);
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
        end
    end

    methods (Test)

        function testRemovesAllBinaryKinds(testCase)
            % Every compiled-binary extension is stripped: MEX of each
            % platform, shared libs, static libs/objects, and executables.
            binaries = { ...
                'a.mexa64', 'a.mexmaci64', 'a.mexmaca64', 'a.mexw64', ...
                'a.mexw32', 'a.mexglx', 'a.mexmac', ...
                'libfoo.dll', 'libfoo.dylib', 'libfoo.so', ...
                'libfoo.a', 'libfoo.lib', 'foo.o', 'tool.exe'};
            for i = 1:numel(binaries)
                touch(fullfile(testCase.TestRoot, binaries{i}));
            end

            count = mip.build.strip_prebuilt_binaries(testCase.TestRoot);

            testCase.verifyEqual(count, numel(binaries));
            for i = 1:numel(binaries)
                testCase.verifyFalse( ...
                    exist(fullfile(testCase.TestRoot, binaries{i}), 'file') > 0, ...
                    sprintf('%s should have been removed', binaries{i}));
            end
        end

        function testRemovesVersionedSonames(testCase)
            % Versioned ELF sonames (libfoo.so.1, libfoo.so.1.2.3) don't end
            % in ".so" so they need the regexp branch, not the suffix list.
            touch(fullfile(testCase.TestRoot, 'libfoo.so.1'));
            touch(fullfile(testCase.TestRoot, 'libbar.so.1.2.3'));

            count = mip.build.strip_prebuilt_binaries(testCase.TestRoot);

            testCase.verifyEqual(count, 2);
            testCase.verifyFalse(exist(fullfile(testCase.TestRoot, 'libfoo.so.1'), 'file') > 0);
            testCase.verifyFalse(exist(fullfile(testCase.TestRoot, 'libbar.so.1.2.3'), 'file') > 0);
        end

        function testKeepsObjGeometryAndSources(testCase)
            % .obj is Wavefront geometry, not a compiled object — it and the
            % source/data files must survive untouched.
            keep = {'cube.obj', 'foo.m', 'bar.cpp', 'README.md', 'data.txt'};
            for i = 1:numel(keep)
                touch(fullfile(testCase.TestRoot, keep{i}));
            end

            count = mip.build.strip_prebuilt_binaries(testCase.TestRoot);

            testCase.verifyEqual(count, 0);
            for i = 1:numel(keep)
                testCase.verifyTrue( ...
                    exist(fullfile(testCase.TestRoot, keep{i}), 'file') > 0, ...
                    sprintf('%s should have survived', keep{i}));
            end
        end

        function testRecursesIntoSubdirectories(testCase)
            % Vendored binaries are typically buried under external/ subdirs,
            % so the scan must reach nested files and leave the dirs in place.
            nested = fullfile(testCase.TestRoot, 'external', 'vendor');
            mkdir(nested);
            touch(fullfile(nested, 'libdep.dylib'));
            touch(fullfile(nested, 'mesh.obj'));

            count = mip.build.strip_prebuilt_binaries(testCase.TestRoot);

            testCase.verifyEqual(count, 1);
            testCase.verifyFalse(exist(fullfile(nested, 'libdep.dylib'), 'file') > 0);
            testCase.verifyTrue(exist(fullfile(nested, 'mesh.obj'), 'file') > 0);
            testCase.verifyTrue(exist(nested, 'dir') > 0);
        end

        function testEmptyTreeReturnsZero(testCase)
            % A tree with nothing to strip returns 0 and removes nothing.
            touch(fullfile(testCase.TestRoot, 'only.m'));
            count = mip.build.strip_prebuilt_binaries(testCase.TestRoot);
            testCase.verifyEqual(count, 0);
            testCase.verifyTrue(exist(fullfile(testCase.TestRoot, 'only.m'), 'file') > 0);
        end

    end

end

function touch(filePath)
% Create an empty file at filePath.
    fid = fopen(filePath, 'w');
    fclose(fid);
end
