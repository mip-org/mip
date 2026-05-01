classdef TestCompareVersions < matlab.unittest.TestCase
%TESTCOMPAREVERSIONS   Tests for mip.resolve.compare_versions.

    methods (Test)

        function testEqualNumeric(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('1.0.0', '1.0.0'), 0);
        end

        function testGreaterNumeric(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('2.0.0', '1.9.9'), 1);
        end

        function testLessNumeric(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('1.0.0', '2.0.0'), -1);
        end

        function testNumericComponentOrderingNotLexical(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('1.10', '1.9'), 1);
            testCase.verifyEqual(mip.resolve.compare_versions('1.9', '1.10'), -1);
        end

        function testDifferentComponentCounts(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('1.0', '1.0.0'), 0);
            testCase.verifyEqual(mip.resolve.compare_versions('1.0.1', '1.0'), 1);
            testCase.verifyEqual(mip.resolve.compare_versions('1.0', '1.0.1'), -1);
        end

        function testNumericOutranksMain(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('0.0.1', 'main'), 1);
            testCase.verifyEqual(mip.resolve.compare_versions('main', '2.0'), -1);
        end

        function testNumericOutranksArbitraryName(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('0.1', 'dev'), 1);
            testCase.verifyEqual(mip.resolve.compare_versions('dev', '0.1'), -1);
        end

        function testMainOutranksMaster(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('main', 'master'), 1);
            testCase.verifyEqual(mip.resolve.compare_versions('master', 'main'), -1);
        end

        function testMasterOutranksOtherName(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('master', 'zeta'), 1);
            testCase.verifyEqual(mip.resolve.compare_versions('zeta', 'master'), -1);
        end

        function testEqualNamed(testCase)
            testCase.verifyEqual(mip.resolve.compare_versions('main', 'main'), 0);
            testCase.verifyEqual(mip.resolve.compare_versions('dev', 'dev'), 0);
        end

        function testOtherNamesAlphabeticallyFirstRanksHigher(testCase)
            % Matches select_best_version's alphabetical-first fallback
            testCase.verifyEqual(mip.resolve.compare_versions('alpha', 'beta'), 1);
            testCase.verifyEqual(mip.resolve.compare_versions('beta', 'alpha'), -1);
        end

        function testSortPlacesLatestNumericAtEnd(testCase)
            % Reproduces the info.m sortVersions scenario from issue #227.
            versions = {'main', '0.5', '1.0', '2.0'};
            sorted = sortVersions(versions);
            testCase.verifyEqual(sorted{end}, '2.0');
        end

        function testSortAmongMixedTiers(testCase)
            versions = {'dev', 'main', '1.0', 'master', '2.0', 'zeta'};
            sorted = sortVersions(versions);
            % Lowest -> highest: zeta, dev (other names, alphabetical-first
            % ranks higher), then master, main, then numeric
            testCase.verifyEqual(sorted, {'zeta', 'dev', 'master', 'main', '1.0', '2.0'});
        end

    end
end

function sorted = sortVersions(versions)
    n = length(versions);
    sorted = versions;
    for i = 2:n
        key = sorted{i};
        j = i - 1;
        while j >= 1 && mip.resolve.compare_versions(sorted{j}, key) > 0
            sorted{j+1} = sorted{j};
            j = j - 1;
        end
        sorted{j+1} = key;
    end
end
