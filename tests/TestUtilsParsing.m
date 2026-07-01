classdef TestUtilsParsing < matlab.unittest.TestCase
%TESTUTILSPARSING   Tests for parse_package_arg, parse_channel_spec,
%   parse_channel_flag, display_fqn, and make_fqn utility functions.

    methods (Test)

        %% parse_package_arg tests

        function testParseBarePackageName(testCase)
            r = mip.parse.parse_package_arg('chebfun');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.type, '');
            testCase.verifyEqual(r.owner, '');
            testCase.verifyEqual(r.channel, '');
            testCase.verifyEqual(r.fqn, '');
            testCase.verifyFalse(r.is_fqn);
            testCase.verifyEqual(r.version, '');
        end

        function testParseGhShorthand(testCase)
            % 3-part shorthand: treated as gh/<owner>/<channel>/<name>
            r = mip.parse.parse_package_arg('mip-org/core/chebfun');
            testCase.verifyEqual(r.name, 'chebfun');
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.owner, 'mip-org');
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
            testCase.verifyEqual(r.owner, 'mip-org');
            testCase.verifyEqual(r.channel, 'core');
            testCase.verifyEqual(r.fqn, 'gh/mip-org/core/chebfun');
            testCase.verifyTrue(r.is_fqn);
        end

        function testParseLocalFqn(testCase)
            r = mip.parse.parse_package_arg('local/mypkg');
            testCase.verifyEqual(r.name, 'mypkg');
            testCase.verifyEqual(r.type, 'local');
            testCase.verifyEqual(r.owner, '');
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
            testCase.verifyEqual(r.owner, 'mip-org');
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

        function testParseGhShorthandCustomOwner(testCase)
            r = mip.parse.parse_package_arg('mylab/custom/mypkg');
            testCase.verifyEqual(r.name, 'mypkg');
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.owner, 'mylab');
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

        function testParseRejectsDotInName(testCase)
            % Dots are not allowed in package names (canonical or input).
            testCase.verifyError(@() mip.parse.parse_package_arg('.github'), ...
                'mip:invalidPackageSpec');
            testCase.verifyError(@() mip.parse.parse_package_arg('my.pkg'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsLeadingHyphenOrUnderscore(testCase)
            % Names must start with a letter or digit.
            testCase.verifyError(@() mip.parse.parse_package_arg('-foo'), ...
                'mip:invalidPackageSpec');
            testCase.verifyError(@() mip.parse.parse_package_arg('_foo'), ...
                'mip:invalidPackageSpec');
        end

        function testParseRejectsTrailingHyphenOrUnderscore(testCase)
            % Names must end with a letter or digit.
            testCase.verifyError(@() mip.parse.parse_package_arg('foo-'), ...
                'mip:invalidPackageSpec');
            testCase.verifyError(@() mip.parse.parse_package_arg('foo_'), ...
                'mip:invalidPackageSpec');
        end

        function testParseAcceptsMixedCase(testCase)
            % User input allows mixed case — the canonical form produced
            % by init/channel is lowercase, but the parser for user input
            % is permissive.
            r = mip.parse.parse_package_arg('MyPkg');
            testCase.verifyEqual(r.name, 'MyPkg');
        end

        %% parse_channel_spec tests

        function testParseChannelEmpty(testCase)
            [owner, ch] = mip.parse.parse_channel_spec('');
            testCase.verifyEqual(owner, 'mip-org');
            testCase.verifyEqual(ch, 'core');
        end

        function testParseChannelCore(testCase)
            [owner, ch] = mip.parse.parse_channel_spec('mip-org/core');
            testCase.verifyEqual(owner, 'mip-org');
            testCase.verifyEqual(ch, 'core');
        end

        function testParseChannelBareNameErrors(testCase)
            testCase.verifyError(@() mip.parse.parse_channel_spec('core'), ...
                'mip:invalidChannel');
            testCase.verifyError(@() mip.parse.parse_channel_spec('dev'), ...
                'mip:invalidChannel');
        end

        function testParseChannelOwnerChannel(testCase)
            [owner, ch] = mip.parse.parse_channel_spec('mylab/custom');
            testCase.verifyEqual(owner, 'mylab');
            testCase.verifyEqual(ch, 'custom');
        end

        function testParseChannelInvalidThreeParts(testCase)
            testCase.verifyError(@() mip.parse.parse_channel_spec('a/b/c'), ...
                'mip:invalidChannel');
        end

        %% flags tests

        function testFlagsNone(testCase)
            [opts, positionals] = mip.parse.flags({'pkg1', 'pkg2'}, struct('channel', ''));
            testCase.verifyEqual(opts.channel, '');
            testCase.verifyEqual(positionals, {'pkg1', 'pkg2'});
        end

        function testFlagsValueFlag(testCase)
            [opts, positionals] = mip.parse.flags({'--channel', 'dev', 'pkg1'}, struct('channel', ''));
            testCase.verifyEqual(opts.channel, 'dev');
            testCase.verifyEqual(positionals, {'pkg1'});
        end

        function testFlagsValueFlagAtEnd(testCase)
            [opts, positionals] = mip.parse.flags({'pkg1', '--channel', 'dev'}, struct('channel', ''));
            testCase.verifyEqual(opts.channel, 'dev');
            testCase.verifyEqual(positionals, {'pkg1'});
        end

        function testFlagsBooleanFlag(testCase)
            [opts, positionals] = mip.parse.flags({'--force', 'pkg1'}, ...
                struct('force', false, 'all', false));
            testCase.verifyTrue(opts.force);
            testCase.verifyFalse(opts.all);
            testCase.verifyEqual(positionals, {'pkg1'});
        end

        function testFlagsUnderscoreMapsToHyphen(testCase)
            [opts, ~] = mip.parse.flags({'--no-compile'}, struct('no_compile', false));
            testCase.verifyTrue(opts.no_compile);
        end

        function testFlagsRepeatableAccumulates(testCase)
            [opts, ~] = mip.parse.flags({'--with', 'examples', '--with', 'tests'}, ...
                struct('with', {{}}));
            testCase.verifyEqual(opts.with, {'examples', 'tests'});
        end

        function testFlagsRepeatedSingleValueErrors(testCase)
            testCase.verifyError(@() mip.parse.flags( ...
                {'--channel', 'a/b', '--channel', 'c/d'}, struct('channel', '')), ...
                'mip:repeatedFlag');
        end

        function testFlagsUnknownFlagErrors(testCase)
            testCase.verifyError(@() mip.parse.flags({'--bogus'}, struct('force', false)), ...
                'mip:unknownFlag');
        end

        function testFlagsAlias(testCase)
            [opts, ~] = mip.parse.flags({'-e'}, struct('editable', false), ...
                struct('e', 'editable'));
            testCase.verifyTrue(opts.editable);
        end

        function testParseChannelShorthandAppliesToFqn(testCase)
            % A 2-part positional arg '<owner>/<pkg>' (where <owner> is not
            % a reserved source-type prefix) is shorthand for the personal
            % channel form 'gh/<owner>/<owner>/<pkg>'.
            r = mip.parse.parse_package_arg('foo/pkg1');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.name, 'pkg1');
            testCase.verifyEqual(r.owner, 'foo');
            testCase.verifyEqual(r.channel, 'foo');
            testCase.verifyEqual(r.fqn, 'gh/foo/foo/pkg1');
        end

        function testParsePersonalChannelShorthandWithVersion(testCase)
            r = mip.parse.parse_package_arg('magland/chunkie@1.2.0');
            testCase.verifyTrue(r.is_fqn);
            testCase.verifyEqual(r.type, 'gh');
            testCase.verifyEqual(r.owner, 'magland');
            testCase.verifyEqual(r.channel, 'magland');
            testCase.verifyEqual(r.name, 'chunkie');
            testCase.verifyEqual(r.fqn, 'gh/magland/magland/chunkie');
            testCase.verifyEqual(r.version, '1.2.0');
        end

        function testParsePersonalShorthandReservedTypesUnchanged(testCase)
            % Reserved source-type prefixes still parse as non-gh FQNs.
            for prefix = {'local', 'fex', 'web', 'mhl'}
                r = mip.parse.parse_package_arg([prefix{1} '/pkg1']);
                testCase.verifyEqual(r.type, prefix{1});
                testCase.verifyEqual(r.name, 'pkg1');
                testCase.verifyEqual(r.owner, '');
                testCase.verifyEqual(r.channel, '');
                testCase.verifyEqual(r.fqn, [prefix{1} '/pkg1']);
            end
        end

        function testFlagsMissingValue(testCase)
            testCase.verifyError(@() mip.parse.flags({'--channel'}, struct('channel', '')), ...
                'mip:missingFlagValue');
        end

        function testFlagsEmptyArgs(testCase)
            [opts, positionals] = mip.parse.flags({}, struct('channel', ''));
            testCase.verifyEqual(opts.channel, '');
            testCase.verifyEqual(positionals, {});
        end

        %% make_fqn tests

        function testMakeFqn(testCase)
            fqn = mip.parse.make_fqn('mip-org', 'core', 'chebfun');
            testCase.verifyEqual(fqn, 'gh/mip-org/core/chebfun');
        end

        function testMakeFqnCustomOwner(testCase)
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

        function testMakeMhlFqn(testCase)
            fqn = mip.parse.make_mhl_fqn('testpkg');
            testCase.verifyEqual(fqn, 'mhl/testpkg');
        end

        function testMakeMhlFqnRoundTrip(testCase)
            fqn = mip.parse.make_mhl_fqn('testpkg');
            r = mip.parse.parse_package_arg(fqn);
            testCase.verifyEqual(r.type, 'mhl');
            testCase.verifyEqual(r.name, 'testpkg');
            testCase.verifyEqual(r.fqn, 'mhl/testpkg');
            testCase.verifyTrue(r.is_fqn);
        end

        function testMakeFqnRoundTrip(testCase)
            fqn = mip.parse.make_fqn('mip-org', 'core', 'chebfun');
            r = mip.parse.parse_package_arg(fqn);
            testCase.verifyEqual(r.owner, 'mip-org');
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

        function testDisplayFqnCollapsesPersonalChannel(testCase)
            % Personal channels (owner == channel) collapse to <owner>/<pkg>.
            testCase.verifyEqual( ...
                mip.parse.display_fqn('gh/magland/magland/chunkie'), ...
                'magland/chunkie');
        end

        function testDisplayFqnDoesNotCollapseDistinctChannel(testCase)
            % owner != channel: keep the 3-part form.
            testCase.verifyEqual( ...
                mip.parse.display_fqn('gh/mip-org/dev/chebfun'), ...
                'mip-org/dev/chebfun');
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

        function testDisplayFqnDoesNotCollapseReservedOwner(testCase)
            % If the owner matches a reserved source-type prefix, the
            % personal-channel collapse is skipped: the collapsed form
            % '<reserved>/<pkg>' would be re-parsed as a non-gh FQN
            % (e.g. 'local/foo' is a local install), breaking the
            % display→parse round-trip.
            for owner = {'local', 'fex', 'web', 'mhl', 'gh'}
                fqn = ['gh/' owner{1} '/' owner{1} '/foo'];
                expected = [owner{1} '/' owner{1} '/foo'];
                testCase.verifyEqual( ...
                    mip.parse.display_fqn(fqn), expected, ...
                    sprintf('owner=%s should not collapse', owner{1}));
            end
        end

    end
end
