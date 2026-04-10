classdef TestSelectBestVariant < matlab.unittest.TestCase
%TESTSELECTBESTVARIANT   Tests for mip.resolve.select_best_variant.

    methods (Test)

        function testEmptyInput(testCase)
            result = mip.resolve.select_best_variant({}, 'linux_x86_64');
            testCase.verifyEmpty(result);
        end

        function testExactMatch(testCase)
            v1 = struct('architecture', 'linux_x86_64', 'name', 'pkg');
            v2 = struct('architecture', 'macos_arm64', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1, v2}, 'linux_x86_64');
            testCase.verifyEqual(result.architecture, 'linux_x86_64');
        end

        function testAnyFallback(testCase)
            v1 = struct('architecture', 'any', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1}, 'linux_x86_64');
            testCase.verifyEqual(result.architecture, 'any');
        end

        function testNoCompatibleVariant(testCase)
            v1 = struct('architecture', 'macos_arm64', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1}, 'linux_x86_64');
            testCase.verifyEmpty(result);
        end

        function testExactPreferredOverAny(testCase)
            v1 = struct('architecture', 'any', 'name', 'pkg');
            v2 = struct('architecture', 'linux_x86_64', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1, v2}, 'linux_x86_64');
            testCase.verifyEqual(result.architecture, 'linux_x86_64');
        end

        function testNumblWasmFallbackForNumblArchitectures(testCase)
            v1 = struct('architecture', 'numbl_wasm', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1}, 'numbl_linux_x86_64');
            testCase.verifyEqual(result.architecture, 'numbl_wasm');
        end

        function testNumblWasmNotFallbackForNonNumbl(testCase)
            v1 = struct('architecture', 'numbl_wasm', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1}, 'linux_x86_64');
            testCase.verifyEmpty(result);
        end

        function testNumblWasmNotFallbackForItself(testCase)
            % numbl_wasm should match itself exactly, not via the fallback rule
            v1 = struct('architecture', 'numbl_wasm', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1}, 'numbl_wasm');
            testCase.verifyEqual(result.architecture, 'numbl_wasm');
        end

        function testExactPreferredOverNumblWasm(testCase)
            v1 = struct('architecture', 'numbl_wasm', 'name', 'pkg');
            v2 = struct('architecture', 'numbl_linux_x86_64', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1, v2}, 'numbl_linux_x86_64');
            testCase.verifyEqual(result.architecture, 'numbl_linux_x86_64');
        end

        function testNumblWasmPreferredOverAny(testCase)
            v1 = struct('architecture', 'any', 'name', 'pkg');
            v2 = struct('architecture', 'numbl_wasm', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1, v2}, 'numbl_macos_arm64');
            testCase.verifyEqual(result.architecture, 'numbl_wasm');
        end

        function testVariantWithoutArchitectureFieldSkipped(testCase)
            v1 = struct('name', 'pkg');
            v2 = struct('architecture', 'any', 'name', 'pkg');
            result = mip.resolve.select_best_variant({v1, v2}, 'linux_x86_64');
            testCase.verifyEqual(result.architecture, 'any');
        end

    end
end
