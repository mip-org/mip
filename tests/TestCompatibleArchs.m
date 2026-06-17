classdef TestCompatibleArchs < matlab.unittest.TestCase
%TESTCOMPATIBLEARCHS   Tests for mip.build.compatible_archs.

    methods (Test)

        function testEndsWithBaseAndAny(testCase)
            % For any host, the list ends with the base arch then 'any'.
            archs = mip.build.compatible_archs('macos_arm64');
            testCase.verifyEqual(archs{end}, 'any');
            testCase.verifyEqual(archs{end-1}, 'macos_arm64');
        end

        function testMacosHasNoSimdLevels(testCase)
            archs = mip.build.compatible_archs('macos_arm64');
            testCase.verifyEqual(archs, {'macos_arm64', 'any'});
        end

        function testNumblWasmFallbackPreserved(testCase)
            archs = mip.build.compatible_archs('numbl_linux_x86_64');
            testCase.verifyEqual(archs, ...
                {'numbl_linux_x86_64', 'numbl_wasm', 'any'});
        end

        function testNumblWasmNotDuplicatedForItself(testCase)
            archs = mip.build.compatible_archs('numbl_wasm');
            testCase.verifyEqual(archs, {'numbl_wasm', 'any'});
        end

        function testLinuxIsSimdAwareAndOrdered(testCase)
            % On a linux_x86_64 host the list begins with any supported SIMD
            % levels (highest first), then the base arch, then 'any'. We don't
            % know the test runner's CPU, so assert structure rather than exact
            % contents.
            archs = mip.build.compatible_archs('linux_x86_64');
            testCase.verifyEqual(archs{end}, 'any');
            testCase.verifyEqual(archs{end-1}, 'linux_x86_64');

            % Every leading entry (if any) must be a descending SIMD level of
            % the base arch.
            levels = [];
            for i = 1:numel(archs) - 2
                tok = regexp(archs{i}, '^linux_x86_64_v([234])$', 'tokens', 'once');
                testCase.verifyNotEmpty(tok, ...
                    sprintf('Unexpected leading arch "%s"', archs{i}));
                levels(end+1) = str2double(tok{1}); %#ok<AGROW>
            end
            testCase.verifyEqual(levels, sort(levels, 'descend'), ...
                'SIMD levels must be listed highest first');
        end

        function testDefaultsToCurrentArch(testCase)
            % Called with no argument it uses the current machine arch; the
            % list must be non-empty and end with 'any'.
            archs = mip.build.compatible_archs();
            testCase.verifyNotEmpty(archs);
            testCase.verifyEqual(archs{end}, 'any');
        end

    end
end
