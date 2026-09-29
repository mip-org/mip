classdef TestFexResolve < matlab.unittest.TestCase
%TESTFEXRESOLVE   Tests for mip.install.resolve_fex_url.
% Live tests against the real File Exchange and MathWorks add-on
% registry. The first two check the page and registry response that the
% resolver depends on, so a change on the MathWorks side fails at the
% step that broke. Skipped in run_tests() when MIP_SKIP_REMOTE is set.
% No MIP_ROOT needed.

    properties (Constant)
        % shadedErrorBar: renamed on File Exchange from 26311-shadederrorbar
        % to 26311-raacampbell-shadederrorbar.
        ShadedErrorBarUuid = 'e56d6dc9-4a80-11e4-9553-005056977bd0'
        FexBase = 'https://www.mathworks.com/matlabcentral/fileexchange/'
        Registry = 'https://addons.mathworks.com/registry/v1/mpm/packages/'
    end

    methods (Test)

        function testLivePageHasAddOnIdentifier(testCase)
            html = webread([testCase.FexBase '26311-shadederrorbar'], webOpts());
            testCase.verifyTrue(contains(html, ...
                ['data-add-on-identifier="' testCase.ShadedErrorBarUuid '"']), ...
                'File Exchange page should carry the add-on UUID');
        end

        function testLiveManifestsListNewestFirst(testCase)
            json = webread([testCase.Registry testCase.ShadedErrorBarUuid '/-/manifests'], ...
                           webOpts());
            data = jsondecode(json);
            testCase.assertNotEmpty(data.manifests);
            % The resolver takes the first entry, so it must be the newest.
            % shadedErrorBar's versions are all numeric, and include both
            % 1.6.0 and 1.65.0, which a string sort would misorder.
            versions = {data.manifests.version};
            testCase.verifyGreaterThan(numel(versions), 1);
            for i = 2:numel(versions)
                testCase.verifyEqual(mip.resolve.compare_versions( ...
                    versions{1}, versions{i}), 1, versions{i});
            end
        end

        function testLiveResolve(testCase)
            zipUrl = mip.install.resolve_fex_url( ...
                [testCase.FexBase '26311-shadederrorbar']);
            testCase.verifyTrue(startsWith(zipUrl, ...
                'https://addons.mathworks.com/downloads/'), zipUrl);
            testCase.verifyTrue(contains(zipUrl, testCase.ShadedErrorBarUuid), zipUrl);
            testCase.verifyTrue(endsWith(zipUrl, '.zip'), zipUrl);
            testCase.verifyFalse(contains(zipUrl, '?'), zipUrl);
        end

        function testLiveUrlFormsAgree(testCase)
            % The original slug, the renamed slug, an id-only URL, and a
            % URL with a query string all name the same submission.
            expected = mip.install.resolve_fex_url( ...
                [testCase.FexBase '26311-shadederrorbar']);
            others = {'26311-raacampbell-shadederrorbar', '26311', ...
                      '26311-shadederrorbar?s_tid=srchtitle'};
            for i = 1:numel(others)
                testCase.verifyEqual(mip.install.resolve_fex_url( ...
                    [testCase.FexBase others{i}]), expected, others{i});
            end
        end

        function testLiveResolveSecondSubmission(testCase)
            % export_fig, so the live checks do not hinge on one page.
            zipUrl = mip.install.resolve_fex_url([testCase.FexBase '23629-export_fig']);
            testCase.verifyTrue(contains(zipUrl, ...
                'e562b2d1-4a80-11e4-9553-005056977bd0'), zipUrl);
            testCase.verifyTrue(endsWith(zipUrl, '.zip'), zipUrl);
        end

        function testLiveSupportPackageErrors(testCase)
            % MathWorks support packages are on File Exchange but not in
            % the add-on registry (zero manifests).
            try
                mip.install.resolve_fex_url([testCase.FexBase ...
                    '52848-matlab-support-for-mingw-w64-c-c-fortran-compiler']);
                testCase.verifyFail('expected an error');
            catch ME
                testCase.verifyEqual(ME.identifier, 'mip:install:fexResolveFailed');
                testCase.verifySubstring(ME.message, 'no published versions');
            end
        end

        function testLiveNonexistentSubmissionErrors(testCase)
            testCase.verifyError(@() mip.install.resolve_fex_url( ...
                [testCase.FexBase '0-nonexistent']), ...
                'mip:install:fexResolveFailed');
        end

    end
end

function opts = webOpts()
% The MathWorks Akamai layer rejects MATLAB's default User-Agent.
    opts = weboptions('Timeout', 30, 'ContentType', 'text', ...
                      'UserAgent', 'curl/8.0');
end
