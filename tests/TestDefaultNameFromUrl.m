classdef TestDefaultNameFromUrl < matlab.unittest.TestCase
%TESTDEFAULTNAMEFROMURL   Tests for mip.install.default_name_from_url.
% Pure string-in/string-out tests; no network, no MIP_ROOT needed.

    methods (Test)

        %% --- File Exchange landing URLs ---

        function testFexSlug(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://www.mathworks.com/matlabcentral/fileexchange/23629-export_fig'), ...
                'export_fig');
        end

        function testFexSlugWithHyphens(testCase)
            % Only the leading '<id>-' is stripped; hyphens inside the
            % slug are preserved.
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://www.mathworks.com/matlabcentral/fileexchange/12345-my-toolbox'), ...
                'my-toolbox');
        end

        function testFexIdOnly_NoDefault(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://www.mathworks.com/matlabcentral/fileexchange/23629'), ...
                '');
        end

        function testFexQueryStringStripped(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://www.mathworks.com/matlabcentral/fileexchange/23629-export_fig?s_tid=srchtitle'), ...
                'export_fig');
        end

        function testFexTrailingSlash(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://www.mathworks.com/matlabcentral/fileexchange/23629-export_fig/'), ...
                'export_fig');
        end

        function testFexUppercaseSlugLowercased(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://www.mathworks.com/matlabcentral/fileexchange/12345-MyToolbox'), ...
                'mytoolbox');
        end

        %% --- GitHub archive URLs ---

        function testGithubArchiveUsesRepoName(testCase)
            % GitHub archives are named after the ref (master.zip), so the
            % repository name is the sensible default instead.
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://github.com/altmany/export_fig/archive/refs/heads/master.zip'), ...
                'export_fig');
        end

        function testGithubArchiveTag_SanitizesRepoName(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://github.com/foo/My.Repo/archive/refs/tags/v1.0.zip'), ...
                'my_repo');
        end

        %% --- Generic .zip URLs ---

        function testGenericZipUsesFileName(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://example.com/downloads/mypkg.zip'), ...
                'mypkg');
        end

        function testGenericZipUppercase(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://example.com/MyPkg.ZIP'), ...
                'mypkg');
        end

        function testGenericZipQueryStringStripped(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://example.com/foo.zip?token=abc'), ...
                'foo');
        end

        function testDotsBecomeUnderscores(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://example.com/pkg-1.2.3.zip'), ...
                'pkg-1_2_3');
        end

        %% --- No derivable name ---

        function testNoDerivableName(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url( ...
                'https://example.com/---.zip'), ...
                '');
        end

        function testNonTextInput(testCase)
            testCase.verifyEqual(mip.install.default_name_from_url(123), '');
        end

    end
end
