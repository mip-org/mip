classdef TestIndexCommand < matlab.unittest.TestCase
%TESTINDEXCOMMAND   Tests for mip.index URL generation.

    methods (Test)

        function testDefaultChannel(testCase)
            url = mip.index();
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-core/index.json');
        end

        function testDefaultChannelExplicit(testCase)
            url = mip.index('mip-org/core');
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-core/index.json');
        end

        function testCustomChannel(testCase)
            url = mip.index('mylab/custom');
            testCase.verifyEqual(url, 'https://mylab.github.io/mip-custom/index.json');
        end

        function testEmptyStringDefaultsToCore(testCase)
            url = mip.index('');
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-core/index.json');
        end

        function testInvalidChannelErrors(testCase)
            testCase.verifyError(@() mip.index('justchannel'), 'mip:invalidChannel');
        end

        function testChannelWithHyphen(testCase)
            url = mip.index('mip-org/test-channel1');
            testCase.verifyEqual(url, 'https://mip-org.github.io/mip-test-channel1/index.json');
        end

    end
end
