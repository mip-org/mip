classdef TestInstallZipUrl < matlab.unittest.TestCase
%TESTINSTALLZIPURL   Tests for `mip install <url> [--name <name>]`.
% Validation tests do not require network. The end-to-end download path
% is covered by the E2E tests at the bottom (skipped under
% MIP_SKIP_REMOTE); the rest focus on argument categorization, flag
% validation, name derivation/prompting, and download-error surfacing.

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            % Ensure no stray MIP_CONFIRM leaks into name prompting.
            setenv('MIP_CONFIRM', '');
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
            setenv('MIP_CONFIRM', testCase.OrigMipConfirm);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        %% --- Removed --url flag ---

        function testUrlFlag_Removed(testCase)
            testCase.verifyError( ...
                @() mip.install('mypkg', '--url', 'https://example.com/foo.zip'), ...
                'mip:install:urlFlagRemoved');
        end

        function testUrlFlag_Removed_NoPositional(testCase)
            testCase.verifyError( ...
                @() mip.install('--url', 'https://example.com/foo.zip'), ...
                'mip:install:urlFlagRemoved');
        end

        %% --- --name flag validation ---

        function testName_RequiresUrl(testCase)
            % --name with a bare package name (no URL) is rejected.
            testCase.verifyError( ...
                @() mip.install('somepkg', '--name', 'foo'), ...
                'mip:install:nameRequiresUrl');
        end

        function testName_RequiresUrl_MhlUrl(testCase)
            % .mhl URLs are mhl sources, not URL install sources.
            testCase.verifyError( ...
                @() mip.install('https://example.com/x.mhl', '--name', 'foo'), ...
                'mip:install:nameRequiresUrl');
        end

        function testName_RequiresUrl_NonZipUrl(testCase)
            % An https URL whose path does not end in .zip is not a URL
            % install source (it is treated as an .mhl download).
            testCase.verifyError( ...
                @() mip.install('https://example.com/foo.tar.gz', '--name', 'foo'), ...
                'mip:install:nameRequiresUrl');
        end

        function testName_TakesSingleUrl(testCase)
            testCase.verifyError( ...
                @() mip.install('https://a.com/x.zip', 'https://b.com/y.zip', ...
                                '--name', 'foo'), ...
                'mip:install:nameTakesSingleUrl');
        end

        function testName_TakesSingleUrl_MixedArgs(testCase)
            testCase.verifyError( ...
                @() mip.install('https://a.com/x.zip', 'otherpkg', ...
                                '--name', 'foo'), ...
                'mip:install:nameTakesSingleUrl');
        end

        function testName_MissingValue_Errors(testCase)
            testCase.verifyError( ...
                @() mip.install('https://example.com/x.zip', '--name'), ...
                'mip:missingFlagValue');
        end

        function testName_RepeatedFlag_Errors(testCase)
            testCase.verifyError( ...
                @() mip.install('https://example.com/x.zip', ...
                                '--name', 'a', '--name', 'b'), ...
                'mip:repeatedFlag');
        end

        function testName_EditableRejected(testCase)
            testCase.verifyError( ...
                @() mip.install('-e', 'https://example.com/x.zip', ...
                                '--name', 'mypkg'), ...
                'mip:install:editableRequiresLocal');
        end

        function testName_InvalidNameRejected(testCase)
            % The name must match the package-name regex (enforced via
            % parse_package_arg).
            testCase.verifyError( ...
                @() mip.install('https://example.com/x.zip', '--name', 'bad name'), ...
                'mip:invalidPackageSpec');
        end

        function testName_UppercaseNameRejected(testCase)
            % The name becomes the canonical install dir / FQN, so it must
            % be lowercase (canonical form). Parse accepts mixed-case user
            % input, but URL installs specifically require canonical.
            testCase.verifyError( ...
                @() mip.install('https://example.com/x.zip', '--name', 'MyPkg'), ...
                'mip:install:invalidName');
        end

        function testName_FqnRejected(testCase)
            testCase.verifyError( ...
                @() mip.install('https://example.com/x.zip', ...
                                '--name', 'mip-org/core/foo'), ...
                'mip:install:invalidName');
        end

        %% --- URL validation ---

        function testUrl_RejectsHttpScheme(testCase)
            % Plain http:// is refused: a MITM could swap the archive
            % and gain code execution once the package is loaded. See
            % #229. An http .zip URL is still routed to the URL install
            % path (not the .mhl path) so this error is reported.
            testCase.verifyError( ...
                @() mip.install('http://example.com/foo.zip', '--name', 'mypkg'), ...
                'mip:install:requireHttps');
        end

        function testUrl_NonHttpScheme_NotAUrlSource(testCase)
            % ftp:// is not an install URL; the argument fails package-spec
            % parsing during categorization.
            testCase.verifyError( ...
                @() mip.install('ftp://example.com/foo.zip', '--name', 'mypkg'), ...
                'mip:install:invalidPackageSpec');
        end

        %% --- .zip URL acceptance (detection) ---

        function testUrl_AcceptsQueryString(testCase)
            % URL with .zip path and query string passes validation; fails
            % downstream at download (unreachable host).
            testCase.verifyError( ...
                @() mip.install('https://127.0.0.1:1/foo.zip?token=abc', ...
                                '--name', 'mypkg'), ...
                'mip:install:zipDownloadFailed');
        end

        function testUrl_AcceptsGitHubArchive(testCase)
            testCase.verifyError( ...
                @() mip.install('https://127.0.0.1:1/foo/bar/archive/refs/heads/main.zip', ...
                                '--name', 'mypkg'), ...
                'mip:install:zipDownloadFailed');
        end

        function testUrl_AcceptsUppercaseExtension(testCase)
            testCase.verifyError( ...
                @() mip.install('https://127.0.0.1:1/Foo.ZIP', '--name', 'mypkg'), ...
                'mip:install:zipDownloadFailed');
        end

        %% --- Name prompting (non-interactive via MIP_CONFIRM) ---

        function testNoName_ConfirmYes_AcceptsDefault(testCase)
            % MIP_CONFIRM=y accepts the URL-derived default name without
            % prompting; the install then proceeds to the download.
            setenv('MIP_CONFIRM', 'y');
            testCase.verifyError( ...
                @() mip.install('https://127.0.0.1:1/foo.zip'), ...
                'mip:install:zipDownloadFailed');
        end

        function testNoName_ConfirmDecline_Errors(testCase)
            setenv('MIP_CONFIRM', 'n');
            testCase.verifyError( ...
                @() mip.install('https://127.0.0.1:1/foo.zip'), ...
                'mip:install:noName');
        end

        function testNoName_ConfirmYes_NoDerivableDefault_Errors(testCase)
            % No valid canonical name can be derived from the URL, so
            % accepting the default yields no name.
            setenv('MIP_CONFIRM', 'y');
            testCase.verifyError( ...
                @() mip.install('https://127.0.0.1:1/---.zip'), ...
                'mip:install:noName');
        end

        %% --- File Exchange URL handling ---

        function testFexUrl_NotRejectedAsNonZip(testCase)
            % File Exchange landing URLs do not end in .zip but are NOT
            % rejected by urlMustBeZip; they go through the FEX resolver.
            % Skip the e2e network call by checking that the error is
            % anything OTHER than urlMustBeZip when resolution fails on a
            % fake FEX-shaped URL.
            if ~isempty(getenv('MIP_SKIP_REMOTE'))
                return;
            end
            try
                mip.install(['https://www.mathworks.com/matlabcentral/' ...
                             'fileexchange/0-nonexistent'], '--name', 'mypkg');
                testCase.verifyFail('expected an error');
            catch ME
                testCase.verifyNotEqual(ME.identifier, 'mip:install:urlMustBeZip', ...
                    'FEX URL should not be rejected as non-zip');
                % Either resolution failed or the resolved URL is bad.
                % Both are acceptable; the test passes as long as it's
                % not urlMustBeZip.
            end
        end

        %% --- End-to-end installs (skipped under MIP_SKIP_REMOTE) ---

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
            mip.install(zipUrl, '--name', 'web_export_fig_test');

            installedDir = fullfile(testCase.TestRoot, 'packages', ...
                                    'web', 'web_export_fig_test');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0, ...
                'Non-FEX zip URL should install under web/');

            fexDir = fullfile(testCase.TestRoot, 'packages', ...
                              'fex', 'web_export_fig_test');
            testCase.verifyFalse(exist(fexDir, 'dir') > 0, ...
                'Non-FEX zip URL should not install under fex/');
        end

        function testWebUrl_E2EDefaultName(testCase)
            % End-to-end install without --name: MIP_CONFIRM=y accepts the
            % default derived from the URL. For a GitHub archive URL the
            % default is the repository name.
            if ~isempty(getenv('MIP_SKIP_REMOTE'))
                return;
            end
            setenv('MIP_CONFIRM', 'y');
            zipUrl = ['https://github.com/altmany/export_fig/archive/' ...
                      'refs/heads/master.zip'];
            mip.install(zipUrl);

            installedDir = fullfile(testCase.TestRoot, 'packages', ...
                                    'web', 'export_fig');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0, ...
                'Default name for a GitHub archive should be the repo name');
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
            mip.install(fexUrl, '--name', 'fex_seb_test');

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
