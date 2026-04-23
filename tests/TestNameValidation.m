classdef TestNameValidation < matlab.unittest.TestCase
%TESTNAMEVALIDATION   Tests for mip.name.is_valid and mip.name.is_valid_canonical.

    methods (Test)

        %% is_valid (user input) — mixed case OK, `-`/`_` both allowed

        function testIsValid_AcceptsLowercase(testCase)
            testCase.verifyTrue(mip.name.is_valid('chebfun'));
            testCase.verifyTrue(mip.name.is_valid('export_fig'));
            testCase.verifyTrue(mip.name.is_valid('export-fig'));
        end

        function testIsValid_AcceptsMixedCase(testCase)
            testCase.verifyTrue(mip.name.is_valid('ChebFun'));
            testCase.verifyTrue(mip.name.is_valid('MyPkg'));
            testCase.verifyTrue(mip.name.is_valid('CAPS'));
        end

        function testIsValid_AcceptsDigits(testCase)
            testCase.verifyTrue(mip.name.is_valid('pkg42'));
            testCase.verifyTrue(mip.name.is_valid('2d_utils'));
            testCase.verifyTrue(mip.name.is_valid('a'));
            testCase.verifyTrue(mip.name.is_valid('1'));
        end

        function testIsValid_RejectsLeadingOrTrailingSeparators(testCase)
            testCase.verifyFalse(mip.name.is_valid('-foo'));
            testCase.verifyFalse(mip.name.is_valid('_foo'));
            testCase.verifyFalse(mip.name.is_valid('foo-'));
            testCase.verifyFalse(mip.name.is_valid('foo_'));
        end

        function testIsValid_RejectsDots(testCase)
            testCase.verifyFalse(mip.name.is_valid('.github'));
            testCase.verifyFalse(mip.name.is_valid('my.pkg'));
            testCase.verifyFalse(mip.name.is_valid('.'));
            testCase.verifyFalse(mip.name.is_valid('..'));
        end

        function testIsValid_RejectsSpecialChars(testCase)
            testCase.verifyFalse(mip.name.is_valid('pkg name'));
            testCase.verifyFalse(mip.name.is_valid('pkg!'));
            testCase.verifyFalse(mip.name.is_valid('pkg/sub'));
            testCase.verifyFalse(mip.name.is_valid('pkg@1.0'));
        end

        function testIsValid_RejectsEmpty(testCase)
            testCase.verifyFalse(mip.name.is_valid(''));
        end

        %% is_valid_canonical — lowercase only; otherwise same rules

        function testIsValidCanonical_AcceptsLowercase(testCase)
            testCase.verifyTrue(mip.name.is_valid_canonical('chebfun'));
            testCase.verifyTrue(mip.name.is_valid_canonical('export_fig'));
            testCase.verifyTrue(mip.name.is_valid_canonical('export-fig'));
            testCase.verifyTrue(mip.name.is_valid_canonical('a'));
            testCase.verifyTrue(mip.name.is_valid_canonical('pkg42'));
        end

        function testIsValidCanonical_RejectsUppercase(testCase)
            testCase.verifyFalse(mip.name.is_valid_canonical('ChebFun'));
            testCase.verifyFalse(mip.name.is_valid_canonical('MyPkg'));
            testCase.verifyFalse(mip.name.is_valid_canonical('A'));
        end

        function testIsValidCanonical_RejectsLeadingOrTrailingSeparators(testCase)
            testCase.verifyFalse(mip.name.is_valid_canonical('-foo'));
            testCase.verifyFalse(mip.name.is_valid_canonical('_foo'));
            testCase.verifyFalse(mip.name.is_valid_canonical('foo-'));
            testCase.verifyFalse(mip.name.is_valid_canonical('foo_'));
        end

        function testIsValidCanonical_RejectsDotsAndSpecials(testCase)
            testCase.verifyFalse(mip.name.is_valid_canonical('.github'));
            testCase.verifyFalse(mip.name.is_valid_canonical('my.pkg'));
            testCase.verifyFalse(mip.name.is_valid_canonical('pkg name'));
        end

        function testIsValidCanonical_RejectsEmpty(testCase)
            testCase.verifyFalse(mip.name.is_valid_canonical(''));
        end

        %% Cross-check: canonical implies valid

        function testValidCanonicalImpliesValid(testCase)
            samples = {'chebfun', 'export_fig', 'export-fig', 'a', 'pkg42', '2d_utils'};
            for i = 1:numel(samples)
                testCase.verifyTrue(mip.name.is_valid_canonical(samples{i}));
                testCase.verifyTrue(mip.name.is_valid(samples{i}));
            end
        end

    end
end
