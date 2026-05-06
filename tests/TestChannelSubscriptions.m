classdef TestChannelSubscriptions < matlab.unittest.TestCase
%TESTCHANNELSUBSCRIPTIONS   Tests for channel subscription persistence
%   and bare-name install resolution against the priority list.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_subs_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        %% --- get/add/remove channels ---

        function testGetChannels_EmptyInitially(testCase)
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {});
        end

        function testAddChannel_PersistsInPriorityOrder(testCase)
            mip.state.add_channel('mylab/dev');
            mip.state.add_channel('acme/extras');
            channels = mip.state.get_channels();
            % Most recent add is highest priority.
            testCase.verifyEqual(channels, {'acme/extras', 'mylab/dev'});
        end

        function testAddChannel_MovesExistingToTop(testCase)
            mip.state.add_channel('a/one');
            mip.state.add_channel('b/two');
            mip.state.add_channel('c/three');
            mip.state.add_channel('a/one');  % move-to-top
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {'a/one', 'c/three', 'b/two'});
        end

        function testAddChannel_ShorthandExpansion(testCase)
            mip.state.add_channel('mylab');  % shorthand for mylab/mylab
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {'mylab/mylab'});
        end

        function testAddChannel_RejectsCore(testCase)
            % core is implicit, adding it is a no-op.
            mip.state.add_channel('mip-org/core');
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {});
        end

        function testAddChannel_InvalidFormatErrors(testCase)
            testCase.verifyError(@() mip.state.add_channel('a/b/c'), ...
                'mip:invalidChannel');
            testCase.verifyError(@() mip.state.add_channel(''), ...
                'mip:invalidChannel');
        end

        function testRemoveChannel_RemovesEntry(testCase)
            mip.state.add_channel('a/one');
            mip.state.add_channel('b/two');
            mip.state.remove_channel('a/one');
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {'b/two'});
        end

        function testRemoveChannel_NonexistentIsNoOp(testCase)
            mip.state.add_channel('a/one');
            mip.state.remove_channel('not/subscribed');
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {'a/one'});
        end

        function testRemoveChannel_ShorthandExpansion(testCase)
            mip.state.add_channel('mylab/mylab');
            mip.state.remove_channel('mylab');  % shorthand
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {});
        end

        function testChannels_PersistAcrossCalls(testCase)
            mip.state.add_channel('a/one');
            mip.state.add_channel('b/two');
            % Simulate process restart by re-reading the file.
            channels1 = mip.state.get_channels();
            channels2 = mip.state.get_channels();
            testCase.verifyEqual(channels1, channels2);
            channelsFile = fullfile(testCase.TestRoot, 'packages', 'channels.txt');
            testCase.verifyTrue(exist(channelsFile, 'file') > 0);
        end

        %% --- Command dispatch (mip channel add/remove/list) ---

        function testCmd_AddRemoveListViaTopLevel(testCase)
            mip('channel', 'add', 'mylab/dev');
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {'mylab/dev'});

            mip('channel', 'remove', 'mylab/dev');
            channels = mip.state.get_channels();
            testCase.verifyEqual(channels, {});
        end

        function testCmd_AddRequiresArgument(testCase)
            testCase.verifyError(@() mip('channel', 'add'), 'mip:noChannel');
        end

        function testCmd_RemoveRequiresArgument(testCase)
            testCase.verifyError(@() mip('channel', 'remove'), 'mip:noChannel');
        end

        function testCmd_NoSubcommand(testCase)
            testCase.verifyError(@() mip('channel'), 'mip:noSubcommand');
        end

        function testCmd_UnknownSubcommand(testCase)
            testCase.verifyError(@() mip('channel', 'bogus'), ...
                'mip:unknownSubcommand');
        end

        %% --- Bare-name install resolution against subscribed channels ---

        function testInstall_BareName_NoSubscriptions_StillUsesCore(testCase)
            % No subscriptions: bare-name install behaves exactly as before.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {'foo'});

            mip.install('foo');  % already installed -> no-op

            corePkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'core', 'foo');
            testCase.verifyTrue(exist(corePkg, 'dir') > 0);
        end

        function testInstall_BareName_ResolvesToSubscribedChannel(testCase)
            % Package only in subscribed channel; bare-name install must
            % find it there once subscribed.
            createTestPackage(testCase.TestRoot, 'mylab', 'dev', 'bar');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/dev', {'bar'});

            mip.state.add_channel('mylab/dev');
            mip.install('bar');  % already installed at mylab/dev/bar -> no-op

            subPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mylab', 'dev', 'bar');
            corePkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'core', 'bar');
            testCase.verifyTrue(exist(subPkg, 'dir') > 0, ...
                'bar should resolve to subscribed channel');
            testCase.verifyFalse(exist(corePkg, 'dir') > 0, ...
                'bar should NOT have been installed under core');
        end

        function testInstall_BareName_NotSubscribedErrors(testCase)
            % Without a subscription, a bare name absent from core fails.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/dev', {'bar'});

            testCase.verifyError(@() mip.install('bar'), ...
                'mip:packageNotFound');
        end

        function testInstall_BareName_CorePrioritizedOverSubscribed(testCase)
            % Both core and a subscribed channel publish 'baz'. Core wins.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'baz');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {'baz'});
            writeChannelIndex(testCase.TestRoot, 'mylab/dev', {'baz'});

            mip.state.add_channel('mylab/dev');
            mip.install('baz');  % no-op (already installed under core)

            corePkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'core', 'baz');
            subPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mylab', 'dev', 'baz');
            testCase.verifyTrue(exist(corePkg, 'dir') > 0, ...
                'baz should resolve to core (priority over subscriptions)');
            testCase.verifyFalse(exist(subPkg, 'dir') > 0);
        end

        function testInstall_BareName_PrioritizesMostRecentSubscription(testCase)
            % Two subscribed channels both publish 'qux'. The most recently
            % added is highest priority and must win. Only the expected
            % target is pre-installed; if resolution picked the wrong
            % channel, install would attempt a download and fail.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'first/first', {'qux'});
            writeChannelIndex(testCase.TestRoot, 'second/second', {'qux'});

            mip.state.add_channel('first/first');
            mip.state.add_channel('second/second');
            % second/second was added last so it is highest-priority.
            createTestPackage(testCase.TestRoot, 'second', 'second', 'qux');

            mip.install('qux');

            secondPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'second', 'second', 'qux');
            firstPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'first', 'first', 'qux');
            testCase.verifyTrue(exist(secondPkg, 'dir') > 0, ...
                'qux should resolve to most-recently-added subscription');
            testCase.verifyFalse(exist(firstPkg, 'dir') > 0);
        end

        function testInstall_BareName_ChannelFlagOverridesSubscriptions(testCase)
            % Explicit --channel disables the priority list.
            createTestPackage(testCase.TestRoot, 'mylab', 'dev', 'bar');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/dev', {'bar'});
            writeChannelIndex(testCase.TestRoot, 'other/place', {'bar'});

            mip.state.add_channel('other/place');
            mip.install('--channel', 'mylab/dev', 'bar');

            mylabPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mylab', 'dev', 'bar');
            otherPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'other', 'place', 'bar');
            testCase.verifyTrue(exist(mylabPkg, 'dir') > 0, ...
                'bar should resolve to --channel value, not subscription');
            testCase.verifyFalse(exist(otherPkg, 'dir') > 0);
        end

        function testInstall_FQN_IgnoresSubscriptions(testCase)
            % FQN args resolve to their explicit channel.
            createTestPackage(testCase.TestRoot, 'mylab', 'dev', 'bar');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/dev', {'bar'});
            writeChannelIndex(testCase.TestRoot, 'other/place', {'bar'});

            mip.state.add_channel('other/place');
            mip.install('mylab/dev/bar');

            mylabPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mylab', 'dev', 'bar');
            otherPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'other', 'place', 'bar');
            testCase.verifyTrue(exist(mylabPkg, 'dir') > 0);
            testCase.verifyFalse(exist(otherPkg, 'dir') > 0);
        end

        function testInstall_MixedBareAndFQN_BareUsesSubscriptions(testCase)
            % Mixed args: bare name uses subscriptions; FQN uses its
            % explicit channel.
            createTestPackage(testCase.TestRoot, 'mylab', 'dev', 'bar');
            createTestPackage(testCase.TestRoot, 'other', 'place', 'foo');
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeChannelIndex(testCase.TestRoot, 'mylab/dev', {'bar'});
            writeChannelIndex(testCase.TestRoot, 'other/place', {'foo'});

            mip.state.add_channel('mylab/dev');
            mip.install('bar', 'other/place/foo');

            barPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mylab', 'dev', 'bar');
            fooPkg = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'other', 'place', 'foo');
            testCase.verifyTrue(exist(barPkg, 'dir') > 0);
            testCase.verifyTrue(exist(fooPkg, 'dir') > 0);
        end

    end
end
