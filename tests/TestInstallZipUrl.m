classdef TestInstallZipUrl < matlab.unittest.TestCase
%TESTINSTALLZIPURL   Tests for `mip install <name> --url <zip-url>`.
% Validation tests do not require network. The end-to-end download path
% is covered by manual smoke testing; these tests focus on argument
% categorization, flag validation, and download-error surfacing.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_zip_test'];
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

        %% --- Flag / positional validation ---

        function testUrl_RequiresPositionalName(testCase)
            testCase.verifyError( ...
                @() mip.install('--url', 'https://example.com/foo.zip'), ...
                'mip:install:urlRequiresName');
        end

        function testUrl_RejectsMultiplePositionals(testCase)
            testCase.verifyError( ...
                @() mip.install('foo', 'bar', '--url', 'https://example.com/x.zip'), ...
                'mip:install:urlTakesSingleName');
        end

        function testUrl_RejectsFqnPositional(testCase)
            testCase.verifyError( ...
                @() mip.install('mip-org/core/foo', '--url', 'https://example.com/x.zip'), ...
                'mip:install:urlTakesSingleName');
        end

        function testUrl_RejectsPathPositional(testCase)
            testCase.verifyError( ...
                @() mip.install('./foo', '--url', 'https://example.com/x.zip'), ...
                'mip:install:urlTakesSingleName');
        end

        function testUrl_RejectsUrlPositional(testCase)
            testCase.verifyError( ...
                @() mip.install('https://other.com/x.zip', ...
                                '--url', 'https://example.com/x.zip'), ...
                'mip:install:urlTakesSingleName');
        end

        function testUrl_MissingValue_Errors(testCase)
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url'), ...
                'mip:install:missingUrlValue');
        end

        function testUrl_RepeatedFlag_Errors(testCase)
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url', 'https://a.com/x.zip', ...
                                '--url', 'https://b.com/y.zip'), ...
                'mip:install:multipleUrls');
        end

        function testUrl_EditableRejected(testCase)
            testCase.verifyError( ...
                @() mip.install('-e', 'mypkg', '--url', 'https://example.com/x.zip'), ...
                'mip:install:editableRequiresLocal');
        end

        function testUrl_InvalidNameRejected(testCase)
            % Positional name must match the package-name regex (enforced
            % via parse_package_arg).
            testCase.verifyError( ...
                @() mip.install('bad name', '--url', 'https://example.com/x.zip'), ...
                'mip:invalidPackageSpec');
        end

        function testUrl_UppercaseNameRejected(testCase)
            % With --url, the positional name becomes the canonical install
            % dir / FQN, so it must be lowercase (canonical form). Parse
            % accepts mixed-case user input, but --url specifically
            % requires canonical.
            testCase.verifyError( ...
                @() mip.install('MyPkg', '--url', 'https://example.com/x.zip'), ...
                'mip:install:invalidName');
        end

        %% --- URL validation (must be a .zip) ---

        function testUrl_RejectsNonZipUrl(testCase)
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url', 'https://example.com/foo.tar.gz'), ...
                'mip:install:urlMustBeZip');
        end

        function testUrl_RejectsMhlUrl(testCase)
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url', 'https://example.com/foo.mhl'), ...
                'mip:install:urlMustBeZip');
        end

        function testUrl_RejectsNonHttpScheme(testCase)
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url', 'ftp://example.com/foo.zip'), ...
                'mip:install:urlMustBeZip');
        end

        function testUrl_RejectsHttpScheme(testCase)
            % Plain http:// is refused: a MITM could swap the archive
            % and gain code execution once the package is loaded. See
            % #229.
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url', 'http://example.com/foo.zip'), ...
                'mip:install:requireHttps');
        end

        function testUrl_RejectsZipOnlyInQueryString(testCase)
            % .zip appears only in query string (not path) -> not a zip URL
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url', 'https://example.com/foo?file=bar.zip'), ...
                'mip:install:urlMustBeZip');
        end

        %% --- .zip URL acceptance (detection) ---

        function testUrl_AcceptsQueryString(testCase)
            % URL with .zip path and query string passes validation; fails
            % downstream at download (unreachable host). Any error that is
            % NOT urlMustBeZip means the URL was accepted as a zip URL.
            try
                mip.install('mypkg', '--url', ...
                    'https://127.0.0.1:1/foo.zip?token=abc');
                testCase.verifyFail('expected a download error');
            catch ME
                testCase.verifyEqual(ME.identifier, 'mip:install:zipDownloadFailed');
            end
        end

        function testUrl_AcceptsGitHubArchive(testCase)
            try
                mip.install('mypkg', '--url', ...
                    'https://127.0.0.1:1/foo/bar/archive/refs/heads/main.zip');
                testCase.verifyFail('expected a download error');
            catch ME
                testCase.verifyEqual(ME.identifier, 'mip:install:zipDownloadFailed');
            end
        end

        function testUrl_AcceptsUppercaseExtension(testCase)
            try
                mip.install('mypkg', '--url', 'https://127.0.0.1:1/Foo.ZIP');
                testCase.verifyFail('expected a download error');
            catch ME
                testCase.verifyEqual(ME.identifier, 'mip:install:zipDownloadFailed');
            end
        end

        %% --- Download failure surfacing ---

        function testUrl_DownloadFailure(testCase)
            testCase.verifyError( ...
                @() mip.install('nope', '--url', 'https://127.0.0.1:1/foo.zip'), ...
                'mip:install:zipDownloadFailed');
        end

        %% --- File Exchange URL handling ---

        function testFexUrl_NotRejectedAsNonZip(testCase)
            % File Exchange landing URLs do not end in .zip but are NOT
            % rejected by urlMustBeZip; they go through the FEX resolver.
            % Skip the e2e network call by checking that the error is
            % anything OTHER than urlMustBeZip when DNS fails on a fake
            % FEX-shaped URL.
            if ~isempty(getenv('MIP_SKIP_REMOTE'))
                return;
            end
            try
                mip.install('mypkg', '--url', ...
                    'https://www.mathworks.com/matlabcentral/fileexchange/0-nonexistent');
                testCase.verifyFail('expected an error');
            catch ME
                testCase.verifyNotEqual(ME.identifier, 'mip:install:urlMustBeZip', ...
                    'FEX URL should not be rejected as non-zip');
                % Either resolution failed or the resolved URL is bad.
                % Both are acceptable; the test passes as long as it's
                % not urlMustBeZip.
            end
        end

        function testFexUrl_AsPositional_RequiresName(testCase)
            % `mip install <FEX URL>` (without --url) should produce a
            % helpful message pointing to the correct syntax, rather than
            % attempting to download the landing page as an .mhl file.
            testCase.verifyError( ...
                @() mip.install('https://www.mathworks.com/matlabcentral/fileexchange/26311-shadederrorbar'), ...
                'mip:install:fexRequiresName');
        end

        function testWebUrl_E2EInstall(testCase)
            % End-to-end install from a generic (non-FEX) .zip URL. Uses a
            % GitHub archive zip as a benign test target. Verifies the
            % package lands under web/ (not fex/) — i.e. the fex/web split
            % routes non-FEX URLs correctly. Silently returns under
            % MIP_SKIP_REMOTE.
            if ~isempty(getenv('MIP_SKIP_REMOTE'))
                return;
            end
            zipUrl = ['https://github.com/altmany/export_fig/archive/' ...
                      'refs/heads/master.zip'];
            mip.install('web_export_fig_test', '--url', zipUrl);

            installedDir = fullfile(testCase.TestRoot, 'packages', ...
                                    'web', 'web_export_fig_test');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0, ...
                'Non-FEX zip URL should install under web/');

            fexDir = fullfile(testCase.TestRoot, 'packages', ...
                              'fex', 'web_export_fig_test');
            testCase.verifyFalse(exist(fexDir, 'dir') > 0, ...
                'Non-FEX zip URL should not install under fex/');
        end

        function testFexUrl_E2EInstall(testCase)
            % End-to-end install from a real File Exchange URL. Uses
            % shadedErrorBar (a small, widely-used plotting utility) as
            % a benign test target. Silently returns under MIP_SKIP_REMOTE
            % (matches the pattern in run_tests.m of conditionally
            % including remote suites).
            if ~isempty(getenv('MIP_SKIP_REMOTE'))
                return;
            end
            fexUrl = ['https://www.mathworks.com/matlabcentral/fileexchange/' ...
                     '26311-shadederrorbar'];
            mip.install('fex_seb_test', '--url', fexUrl);

            installedDir = fullfile(testCase.TestRoot, 'packages', ...
                                    'fex', 'fex_seb_test');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0, ...
                'FEX package should install under fex/');

            % The auto-generated mip.yaml's repository field should be
            % the resolved zip URL (UUID path), not the original FEX URL.
            innerYaml = fullfile(installedDir, 'fex_seb_test', 'mip.yaml');
            cfg = mip.config.read_mip_yaml(fileparts(innerYaml));
            testCase.verifyTrue(endsWith(lower(cfg.repository), '.zip'), ...
                'repository should be the resolved .zip URL');
            testCase.verifyTrue(contains(cfg.repository, 'mlc-downloads'), ...
                'repository should be the UUID-based mlc-downloads URL');
            testCase.verifyFalse(contains(cfg.repository, '?'), ...
                'repository should have query string stripped');
        end

    end
end
