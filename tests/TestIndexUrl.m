classdef TestIndexUrl < matlab.unittest.TestCase
%TESTINDEXURL   Tests for mip.channel.index_url URL generation.

    methods (Test)

        function testDefaultChannel(testCase)
            url = mip.channel.index_url();
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-core/index.json');
        end

        function testDefaultChannelExplicit(testCase)
            url = mip.channel.index_url('mip-org/core');
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-core/index.json');
        end

        function testCustomChannel(testCase)
            url = mip.channel.index_url('mylab/custom');
            testCase.verifyEqual(url, 'https://mylab.github.io/mip-custom/index.json');
        end

        function testEmptyStringDefaultsToCore(testCase)
            url = mip.channel.index_url('');
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-core/index.json');
        end

        function testInvalidChannelErrors(testCase)
            testCase.verifyError(@() mip.channel.index_url('justchannel'), 'mip:invalidChannel');
        end

        function testChannelWithHyphen(testCase)
            url = mip.channel.index_url('mip-org/test-channel1');
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-test-channel1/index.json');
        end

    end
end
