classdef TestIsNumericVersion < matlab.unittest.TestCase
%TESTISNUMERICVERSION   Tests for mip.resolve.is_numeric_version.

    methods (Test)

        function testNumericVersions(testCase)
            testCase.verifyTrue(mip.resolve.is_numeric_version('1'));
            testCase.verifyTrue(mip.resolve.is_numeric_version('0.5.0'));
            testCase.verifyTrue(mip.resolve.is_numeric_version('1.2.3'));
            testCase.verifyTrue(mip.resolve.is_numeric_version('10.20'));
        end

        function testNonNumericVersions(testCase)
            testCase.verifyFalse(mip.resolve.is_numeric_version('main'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('master'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('v1.2.3'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('1.2.3-beta'));
            testCase.verifyFalse(mip.resolve.is_numeric_version(''));
        end

        function testComponentsMustBeAllDigits(testCase)
            % Signs, exponents, and named floats parse as numbers via
            % str2double but are not numeric version components. This
            % matches the channel build's (mip_channel_tools) definition.
            testCase.verifyFalse(mip.resolve.is_numeric_version('1e3'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('+1.2'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('-1'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('inf'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('1.'));
            testCase.verifyFalse(mip.resolve.is_numeric_version('.5'));
        end

    end
end
