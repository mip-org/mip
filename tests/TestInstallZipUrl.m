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

        function testFxUrl_NotRejectedAsNonZip(testCase)
            % File Exchange landing URLs do not end in .zip but are NOT
            % rejected by urlMustBeZip; they go through the FX resolver.
            % Skip the e2e network call by checking that the error is
            % anything OTHER than urlMustBeZip when DNS fails on a fake
            % FX-shaped URL.
            try
                mip.install('mypkg', '--url', ...
                    'https://www.mathworks.com/matlabcentral/fileexchange/0-nonexistent');
                testCase.verifyFail('expected an error');
            catch ME
                testCase.verifyNotEqual(ME.identifier, 'mip:install:urlMustBeZip', ...
                    'FX URL should not be rejected as non-zip');
                % Either resolution failed or the resolved URL is bad.
                % Both are acceptable; the test passes as long as it's
                % not urlMustBeZip.
            end
        end

        function testFxUrl_E2EInstall(testCase)
            % End-to-end install from a real File Exchange URL. Uses
            % shadedErrorBar (a small, widely-used plotting utility) as
            % a benign test target. Silently returns under MIP_SKIP_REMOTE
            % (matches the pattern in run_tests.m of conditionally
            % including remote suites).
            if ~isempty(getenv('MIP_SKIP_REMOTE'))
                return;
            end
            fxUrl = ['https://www.mathworks.com/matlabcentral/fileexchange/' ...
                     '26311-shadederrorbar'];
            mip.install('fx_seb_test', '--url', fxUrl);

            installedDir = fullfile(testCase.TestRoot, 'packages', ...
                                    'local', 'local', 'fx_seb_test');
            testCase.verifyTrue(exist(installedDir, 'dir') > 0, ...
                'FX package should install under local/local/');

            % The auto-generated mip.yaml's repository field should be
            % the resolved zip URL (UUID path), not the original FX URL.
            innerYaml = fullfile(installedDir, 'fx_seb_test', 'mip.yaml');
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
