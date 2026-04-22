classdef TestUtilsParsing < matlab.unittest.TestCase
%TESTUTILSPARSING   Tests for parse_package_arg, parse_channel_spec,
%   parse_channel_flag, display_fqn, and make_fqn utility functions.

    methods (Test)

        %% parse_package_arg tests

        function testParseBarePackageName(testCase)
            r = mip.parse.parse_package_arg('chebfun');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.type, '');
            testCase.verifyEqual(r.org, '');
            testCase.verifyEqual(r.channel, '');
            testCase.verifyEqual(r.fqn, '');
            testCase.verifyFalse(r.is_fqn);
            testCase.verifyEqual(r.version, '');
        end

        function testParseGhShorthand(testCase)
            % 3-part shorthand: treated as gh/<org>/<channel>/<name>
            r = mip.parse.parse_package_arg('mip-org/core/chebfun');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.fqn, 'gh/mip-org/core/chebfun');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.version, '');
        end

        function testParseGhExplicit(testCase)
            % 4-part canonical form
            r = mip.parse.parse_package_arg('gh/mip-org/core/chebfun');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.fqn, 'gh/mip-org/core/chebfun');
            testCase.verifyTrue(r.is_fqn);
        end

        function testParseLocalFqn(testCase)
            r = mip.parse.parse_package_arg('local/mypkg');
            testCase.verifyEqual(r.name, 'mypkg');
            testCase.verifyEqual(r.type, 'local');
            testCase.verifyEqual(r.org, '');
            testCase.verifyEqual(r.channel, '');
            testCase.verifyEqual(r.fqn, 'local/mypkg');
            testCase.verifyTrue(r.is_fqn);
        end

        function testParseFexFqn(testCase)
            r = mip.parse.parse_package_arg('fex/fex_pkg');
            testCase.verifyEqual(r.name, 'fex_pkg');
            testCase.verifyEqual(r.type, 'fex');
            testCase.verifyEqual(r.fqn, 'fex/fex_pkg');
            testCase.verifyTrue(r.is_fqn);
        end

        function testParseBareNameWithVersion(testCase)
            r = mip.parse.parse_package_arg('chebfun@1.2.0');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyFalse(r.is_fqn);
            testCase.verifyEqual(r.version, '1.2.0');
        end

        function testParseGhShorthandWithVersion(testCase)
            r = mip.parse.parse_package_arg('mip-org/core/mip@main');
            testCase.verifyEqual(r.name, 'mip');
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.fqn, 'gh/mip-org/core/mip');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.version, 'main');
        end

        function testParseGhExplicitWithVersion(testCase)
            r = mip.parse.parse_package_arg('gh/mip-org/core/mip@main');
            testCase.verifyEqual(r.name, 'mip');
            testCase.verifyEqual(r.fqn, 'gh/mip-org/core/mip');
            testCase.verifyEqual(r.version, 'main');
        end

        function testParseLocalFqnWithVersion(testCase)
            r = mip.parse.parse_package_arg('local/mypkg@1.0.0');
            testCase.verifyEqual(r.name, 'mypkg');
            testCase.verifyEqual(r.type, 'local');
            testCase.verifyEqual(r.fqn, 'local/mypkg');
            testCase.verifyEqual(r.version, '1.0.0');
        end

        function testParseGhShorthandCustomOrg(testCase)
            r = mip.parse.parse_package_arg('mylab/custom/mypkg');
            testCase.verifyEqual(r.name, 'mypkg');
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.org, 'mylab');
            testCase.verifyEqual(r.channel, 'custom');
            testCase.verifyEqual(r.fqn, 'gh/mylab/custom/mypkg');
            testCase.verifyTrue(r.is_fqn);
        end

        function testParseTwoPartGhErrors(testCase)
            % 'gh/foo' is incomplete and should be rejected.
            testCase.verifyError(@() mip.parse.parse_package_arg('gh/foo'), ...
                'mip:invalidPackageSpec');
        end

        function testParseFourPartNonGhErrors(testCase)
            testCase.verifyError(@() mip.parse.parse_package_arg('zz/org/ch/pkg'), ...
                'mip:invalidPackageSpec');
        end

        function testParseFivePartErrors(testCase)
            testCase.verifyError(@() mip.parse.parse_package_arg('a/b/c/d/e'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsDot(testCase)
            testCase.verifyError(@() mip.parse.parse_package_arg('.'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsDoubleDot(testCase)
            testCase.verifyError(@() mip.parse.parse_package_arg('..'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsSpecialChars(testCase)
            testCase.verifyError(@() mip.parse.parse_package_arg('pkg name'), ...
                'mip:invalidPackageSpec');
            testCase.verifyError(@() mip.parse.parse_package_arg('pkg!'), ...
                'mip:invalidPackageSpec');
        end

        function testParseAcceptsDotInName(testCase)
            r = mip.parse.parse_package_arg('.github');
            testCase.verifyEqual(r.name, '.github');
        end

        %% parse_channel_spec tests

        function testParseChannelEmpty(testCase)
            [org, ch] = mip.parse.parse_channel_spec('');
            testCase.verifyEqual(org, 'mip-org');
            testCase.verifyEqual(ch, 'core');
        end

        function testParseChannelCore(testCase)
            [org, ch] = mip.parse.parse_channel_spec('mip-org/core');
            testCase.verifyEqual(org, 'mip-org');
            testCase.verifyEqual(ch, 'core');
        end

        function testParseChannelBareNameErrors(testCase)
            testCase.verifyError(@() mip.parse.parse_channel_spec('core'), ...
                'mip:invalidChannel');
            testCase.verifyError(@() mip.parse.parse_channel_spec('dev'), ...
                'mip:invalidChannel');
        end

        function testParseChannelOwnerChannel(testCase)
            [org, ch] = mip.parse.parse_channel_spec('mylab/custom');
            testCase.verifyEqual(org, 'mylab');
            testCase.verifyEqual(ch, 'custom');
        end

        function testParseChannelInvalidThreeParts(testCase)
            testCase.verifyError(@() mip.parse.parse_channel_spec('a/b/c'), ...
                'mip:invalidChannel');
        end

        %% parse_channel_flag tests

        function testParseChannelFlagNone(testCase)
            [ch, remaining] = mip.parse.parse_channel_flag({'pkg1', 'pkg2'});
            testCase.verifyEqual(ch, '');
            testCase.verifyEqual(remaining, {'pkg1', 'pkg2'});
        end

        function testParseChannelFlagPresent(testCase)
            [ch, remaining] = mip.parse.parse_channel_flag({'--channel', 'dev', 'pkg1'});
            testCase.verifyEqual(ch, 'dev');
            testCase.verifyEqual(remaining, {'pkg1'});
        end

        function testParseChannelFlagAtEnd(testCase)
            [ch, remaining] = mip.parse.parse_channel_flag({'pkg1', '--channel', 'dev'});
            testCase.verifyEqual(ch, 'dev');
            testCase.verifyEqual(remaining, {'pkg1'});
        end

        function testParseChannelFlagOwnerChannel(testCase)
            [ch, remaining] = mip.parse.parse_channel_flag({'--channel', 'mylab/custom', 'pkg1'});
            testCase.verifyEqual(ch, 'mylab/custom');
            testCase.verifyEqual(remaining, {'pkg1'});
        end

        function testParseChannelFlagMissingValue(testCase)
            testCase.verifyError(@() mip.parse.parse_channel_flag({'--channel'}), ...
                'mip:missingChannelValue');
        end

        function testParseChannelFlagEmptyArgs(testCase)
            [ch, remaining] = mip.parse.parse_channel_flag({});
            testCase.verifyEqual(ch, '');
            testCase.verifyEqual(remaining, {});
        end

        %% make_fqn tests

        function testMakeFqn(testCase)
            fqn = mip.parse.make_fqn('mip-org', 'core', 'chebfun');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/chebfun');
        end

        function testMakeFqnCustomOrg(testCase)
            fqn = mip.parse.make_fqn('mylab', 'custom', 'mypkg');
            testCase.verifyEqual(fqn, 'gh/mylab/custom/mypkg');
        end

        function testMakeLocalFqn(testCase)
            fqn = mip.parse.make_local_fqn('testpkg');
            testCase.verifyEqual(fqn, 'local/testpkg');
        end

        function testMakeFexFqn(testCase)
            fqn = mip.parse.make_fex_fqn('testpkg');
            testCase.verifyEqual(fqn, 'fex/testpkg');
        end

        function testMakeWebFqn(testCase)
            fqn = mip.parse.make_web_fqn('testpkg');
            testCase.verifyEqual(fqn, 'web/testpkg');
        end

        function testMakeFqnRoundTrip(testCase)
            fqn = mip.parse.make_fqn('mip-org', 'core', 'chebfun');
            r = mip.parse.parse_package_arg(fqn);
            testCase.verifyEqual(r.org, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyTrue(r.is_fqn);
        end

        %% display_fqn tests

        function testDisplayFqnStripsGh(testCase)
            testCase.verifyEqual( ...
                mip.parse.display_fqn('gh/mip-org/core/chebfun'), ...
                'mip-org/core/chebfun');
        end

        function testDisplayFqnLocalUnchanged(testCase)
            testCase.verifyEqual( ...
                mip.parse.display_fqn('local/mypkg'), 'local/mypkg');
        end

        function testDisplayFqnFexUnchanged(testCase)
            testCase.verifyEqual( ...
                mip.parse.display_fqn('fex/bar'), 'fex/bar');
        end

        function testDisplayFqnWebUnchanged(testCase)
            testCase.verifyEqual( ...
                mip.parse.display_fqn('web/bar'), 'web/bar');
        end

    end
end
