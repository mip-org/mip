classdef TestUtilsParsing < matlab.unittest.TestCase
%TESTUTILSPARSING   Tests for parse_package_arg, parse_channel_spec,
%   parse_channel_flag, and make_fqn utility functions.

    methods (Test)

        %% parse_package_arg tests

        function testParseBarePackageName(testCase)
            r = mip.utils.parse_package_arg('chebfun');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.org, '');
            testCase.verifyEqual(r.channel, '');
            testCase.verifyFalse(r.is_fqn);
            testCase.verifyEqual(r.version, '');
        end

        function testParseFQN(testCase)
            r = mip.utils.parse_package_arg('mip-org/core/chebfun');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.version, '');
        end

        function testParseBareNameWithVersion(testCase)
            r = mip.utils.parse_package_arg('chebfun@1.2.0');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyFalse(r.is_fqn);
            testCase.verifyEqual(r.version, '1.2.0');
        end

        function testParseFQNWithVersion(testCase)
            r = mip.utils.parse_package_arg('mip-org/core/mip@main');
            testCase.verifyEqual(r.name, 'mip');
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.version, 'main');
        end

        function testParseFQNCustomOrg(testCase)
            r = mip.utils.parse_package_arg('mylab/custom/mypkg');
            testCase.verifyEqual(r.name, 'mypkg');
            testCase.verifyEqual(r.org, 'mylab');
            testCase.verifyEqual(r.channel, 'custom');
            testCase.verifyTrue(r.is_fqn);
        end

        function testParseInvalidTwoParts(testCase)
            testCase.verifyError(@() mip.utils.parse_package_arg('a/b'), ...
                'mip:invalidPackageSpec');
        end

        function testParseInvalidFourParts(testCase)
            testCase.verifyError(@() mip.utils.parse_package_arg('a/b/c/d'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsDot(testCase)
            testCase.verifyError(@() mip.utils.parse_package_arg('.'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsDoubleDot(testCase)
            testCase.verifyError(@() mip.utils.parse_package_arg('..'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsSpecialChars(testCase)
            testCase.verifyError(@() mip.utils.parse_package_arg('pkg name'), ...
                'mip:invalidPackageSpec');
            testCase.verifyError(@() mip.utils.parse_package_arg('pkg!'), ...
                'mip:invalidPackageSpec');
        end

        function testParseAcceptsDotInName(testCase)
            r = mip.utils.parse_package_arg('.github');
            testCase.verifyEqual(r.name, '.github');
        end

        %% parse_channel_spec tests

        function testParseChannelEmpty(testCase)
            [org, ch] = mip.utils.parse_channel_spec('');
            testCase.verifyEqual(org, 'mip-org');
            testCase.verifyEqual(ch, 'core');
        end

        function testParseChannelCore(testCase)
            [org, ch] = mip.utils.parse_channel_spec('mip-org/core');
            testCase.verifyEqual(org, 'mip-org');
            testCase.verifyEqual(ch, 'core');
        end

        function testParseChannelBareNameErrors(testCase)
            testCase.verifyError(@() mip.utils.parse_channel_spec('core'), ...
                'mip:invalidChannel');
            testCase.verifyError(@() mip.utils.parse_channel_spec('dev'), ...
                'mip:invalidChannel');
        end

        function testParseChannelOwnerChannel(testCase)
            [org, ch] = mip.utils.parse_channel_spec('mylab/custom');
            testCase.verifyEqual(org, 'mylab');
            testCase.verifyEqual(ch, 'custom');
        end

        function testParseChannelInvalidThreeParts(testCase)
            testCase.verifyError(@() mip.utils.parse_channel_spec('a/b/c'), ...
                'mip:invalidChannel');
        end

        %% parse_channel_flag tests

        function testParseChannelFlagNone(testCase)
            [ch, remaining] = mip.utils.parse_channel_flag({'pkg1', 'pkg2'});
            testCase.verifyEqual(ch, '');
            testCase.verifyEqual(remaining, {'pkg1', 'pkg2'});
        end

        function testParseChannelFlagPresent(testCase)
            [ch, remaining] = mip.utils.parse_channel_flag({'--channel', 'dev', 'pkg1'});
            testCase.verifyEqual(ch, 'dev');
            testCase.verifyEqual(remaining, {'pkg1'});
        end

        function testParseChannelFlagAtEnd(testCase)
            [ch, remaining] = mip.utils.parse_channel_flag({'pkg1', '--channel', 'dev'});
            testCase.verifyEqual(ch, 'dev');
            testCase.verifyEqual(remaining, {'pkg1'});
        end

        function testParseChannelFlagOwnerChannel(testCase)
            [ch, remaining] = mip.utils.parse_channel_flag({'--channel', 'mylab/custom', 'pkg1'});
            testCase.verifyEqual(ch, 'mylab/custom');
            testCase.verifyEqual(remaining, {'pkg1'});
        end

        function testParseChannelFlagMissingValue(testCase)
            testCase.verifyError(@() mip.utils.parse_channel_flag({'--channel'}), ...
                'mip:missingChannelValue');
        end

        function testParseChannelFlagEmptyArgs(testCase)
            [ch, remaining] = mip.utils.parse_channel_flag({});
            testCase.verifyEqual(ch, '');
            testCase.verifyEqual(remaining, {});
        end

        %% make_fqn tests

        function testMakeFqn(testCase)
            fqn = mip.utils.make_fqn('mip-org', 'core', 'chebfun');
            testCase.verifyEqual(fqn, 'mip-org/core/chebfun');
        end

        function testMakeFqnCustomOrg(testCase)
            fqn = mip.utils.make_fqn('mylab', 'custom', 'mypkg');
            testCase.verifyEqual(fqn, 'mylab/custom/mypkg');
        end

        function testMakeFqnLocal(testCase)
            fqn = mip.utils.make_fqn('local', 'local', 'testpkg');
            testCase.verifyEqual(fqn, 'local/local/testpkg');
        end

        function testMakeFqnRoundTrip(testCase)
            fqn = mip.utils.make_fqn('mip-org', 'core', 'chebfun');
            r = mip.utils.parse_package_arg(fqn);
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyTrue(r.is_fqn);
        end

    end
end
