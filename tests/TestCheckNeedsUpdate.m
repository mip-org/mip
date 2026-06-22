classdef TestCheckNeedsUpdate < matlab.unittest.TestCase
%TESTCHECKNEEDSUPDATE   Unit tests for mip.state.check_needs_update.
%
%   check_needs_update decides whether `mip update` should replace an
%   installed package. It keys off the version and, for matching
%   versions, the build timestamp (not the commit hash).

    methods (Test)

        function testDifferentVersion_NeedsUpdate(testCase)
            installed = struct('version', '1.0.0', 'timestamp', '2026-01-01T00:00:00Z');
            latest    = struct('version', '2.0.0', 'timestamp', '2026-01-01T00:00:00Z');
            testCase.verifyTrue(mip.state.check_needs_update(installed, latest));
        end

        function testSameVersion_NewerTimestamp_NeedsUpdate(testCase)
            installed = struct('version', 'main', 'timestamp', '2026-01-01T00:00:00Z');
            latest    = struct('version', 'main', 'timestamp', '2026-06-01T00:00:00Z');
            testCase.verifyTrue(mip.state.check_needs_update(installed, latest));
        end

        function testSameVersion_SameTimestamp_NoUpdate(testCase)
            installed = struct('version', 'main', 'timestamp', '2026-06-01T00:00:00Z');
            latest    = struct('version', 'main', 'timestamp', '2026-06-01T00:00:00Z');
            testCase.verifyFalse(mip.state.check_needs_update(installed, latest));
        end

        function testSameVersion_OlderChannelTimestamp_NeedsUpdate(testCase)
            % A differing timestamp triggers an update regardless of
            % direction, matching the channel's recorded build.
            installed = struct('version', 'main', 'timestamp', '2026-06-01T00:00:00Z');
            latest    = struct('version', 'main', 'timestamp', '2026-01-01T00:00:00Z');
            testCase.verifyTrue(mip.state.check_needs_update(installed, latest));
        end

        function testLatestMissingTimestamp_NoUpdate(testCase)
            % Legacy channel entry with no timestamp: nothing to compare,
            % so leave the installed package as-is.
            installed = struct('version', 'main', 'timestamp', '2026-01-01T00:00:00Z');
            latest    = struct('version', 'main');
            testCase.verifyFalse(mip.state.check_needs_update(installed, latest));
        end

        function testInstalledMissingTimestamp_NeedsUpdate(testCase)
            % Installed package predates timestamp tracking but the channel
            % now records one: treat as an update.
            installed = struct('version', 'main');
            latest    = struct('version', 'main', 'timestamp', '2026-06-01T00:00:00Z');
            testCase.verifyTrue(mip.state.check_needs_update(installed, latest));
        end

    end
end
