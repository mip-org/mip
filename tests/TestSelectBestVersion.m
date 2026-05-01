classdef TestSelectBestVersion < matlab.unittest.TestCase
%TESTSELECTBESTVERSION   Tests for mip.resolve.select_best_version.

    methods (Test)

        function testEmptyInput(testCase)
            result = mip.resolve.select_best_version({});
            testCase.verifyEqual(result, '');
        end

        function testSingleNumericVersion(testCase)
            result = mip.resolve.select_best_version({'1.0.0'});
            testCase.verifyEqual(result, '1.0.0');
        end

        function testMultipleNumericVersions_SelectsHighest(testCase)
            result = mip.resolve.select_best_version({'1.0.0', '2.1.0', '1.5.3'});
            testCase.verifyEqual(result, '2.1.0');
        end

        function testNumericVersions_DifferentComponentCounts(testCase)
            result = mip.resolve.select_best_version({'1.0', '1.0.1'});
            testCase.verifyEqual(result, '1.0.1');
        end

        function testNumericVersions_MajorMinorPatch(testCase)
            result = mip.resolve.select_best_version({'1.9.0', '1.10.0'});
            testCase.verifyEqual(result, '1.10.0');
        end

        function testNumericPreferredOverNonNumeric(testCase)
            result = mip.resolve.select_best_version({'main', '0.1.0', 'master'});
            testCase.verifyEqual(result, '0.1.0');
        end

        function testMainPreferredOverMaster(testCase)
            result = mip.resolve.select_best_version({'master', 'main'});
            testCase.verifyEqual(result, 'main');
        end

        function testAlphabeticallyFirstWhenNoSpecialNames(testCase)
            result = mip.resolve.select_best_version({'charlie', 'alpha', 'bravo'});
            testCase.verifyEqual(result, 'alpha');
        end

        function testSingleNonNumericVersion(testCase)
            result = mip.resolve.select_best_version({'main'});
            testCase.verifyEqual(result, 'main');
        end

        function testMainOnly(testCase)
            result = mip.resolve.select_best_version({'dev', 'main', 'nightly'});
            testCase.verifyEqual(result, 'main');
        end

        function testMasterOnly(testCase)
            result = mip.resolve.select_best_version({'dev', 'master', 'nightly'});
            testCase.verifyEqual(result, 'master');
        end

    end
end
