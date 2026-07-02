classdef TestAvailRemote < matlab.unittest.TestCase
%TESTAVAILREMOTE   Network-required tests for mip avail display.
%
%   mip avail always re-downloads the channel index (bypassing the cache),
%   so these tests exercise it against the real channels. The default
%   mip-org/core channel must be listed with bare names; any other channel
%   must be listed with qualified names.
%
%   Skipped in run_tests() when MIP_SKIP_REMOTE is set.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_avail_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
        end
    end

    methods (Test)

        function testCoreChannel_ShowsBareNames(testCase)
            out = evalc('mip.avail()');

            % The mip package itself is always published to mip-org/core,
            % so it must appear as a bare name on its own line.
            testCase.verifyTrue(~isempty(regexp(out, '^  mip$', 'once', 'lineanchors')), ...
                'Core channel packages should be listed as bare names');

            % No package line should carry the channel prefix. (The
            % "Using channel: mip-org/core" header has no trailing slash,
            % so checking for "mip-org/core/" only matches package lines.)
            testCase.verifyFalse(contains(out, 'mip-org/core/'), ...
                'Core channel packages should not be shown with qualified names');
        end

        function testOtherChannel_ShowsQualifiedNames(testCase)
            out = evalc('mip.avail(''--channel'', ''mip-org/test-channel1'')');

            testCase.verifyTrue(contains(out, '  mip-org/test-channel1/alpha'), ...
                'Non-core channel packages should be shown with qualified names');
            testCase.verifyTrue(isempty(regexp(out, '^  alpha$', 'once', 'lineanchors')), ...
                'Non-core channel packages should not be listed as bare names');
        end

    end

end
