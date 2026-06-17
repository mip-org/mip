classdef TestDetectCpuLevel < matlab.unittest.TestCase
%TESTDETECTCPULEVEL   Tests for mip.build.detect_cpu_level.
%
% Runs on whatever CPU the test host has, so it asserts the contract (a valid
% level in 1..4, returned without error) rather than a specific value. On the
% mip CI matrix this exercises the Linux /proc/cpuinfo path and, on the Windows
% runner, the bundled cpu_level.ps1 detector.

    methods (Test)

        function testReturnsIntegerLevel1to4(testCase)
            level = mip.build.detect_cpu_level();
            testCase.verifyTrue(isnumeric(level) && isscalar(level));
            testCase.verifyTrue(level >= 1 && level <= 4);
            testCase.verifyEqual(level, round(level), ...
                'Level must be an integer');
        end

        function testStableAcrossCalls(testCase)
            testCase.verifyEqual(mip.build.detect_cpu_level(), ...
                mip.build.detect_cpu_level());
        end

        function testNonX86HostsReturnBaseline(testCase)
            % On Apple Silicon (and any non-x86-64 host) the level is
            % meaningless and the function returns the baseline (1).
            if ~strcmp(computer('arch'), 'maca64')
                return
            end
            testCase.verifyEqual(mip.build.detect_cpu_level(), 1);
        end

    end
end
