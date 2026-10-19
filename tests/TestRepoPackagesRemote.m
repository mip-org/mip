classdef TestRepoPackagesRemote < matlab.unittest.TestCase
%TESTREPOPACKAGESREMOTE   Network-required tests for repository packages (MEP 10).
%
% Whether a repository publishes a mip package is decided by an HTTP 404
% on its index, which only a real request can produce. These tests use a
% repository name that does not exist, so the request returns 404, while
% the personal-channel index is served from the fetch_index cache.

    properties
        OrigMipRoot
        TestRoot
        SourceDir
    end

    properties (Constant)
        MissingRepo = 'mip-test-no-such-repo-8c1f'
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_repo_remote_test'];
            testCase.SourceDir = [tempname '_mip_repo_remote_src'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.SourceDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            for d = {testCase.TestRoot, testCase.SourceDir}
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        function testMissingIndexRaisesNotPublished(testCase)
            testCase.verifyError(@() mip.channel.fetch_index( ...
                ['github.com/mip-org/' testCase.MissingRepo]), 'mip:repo:notPublished');
        end

        function testTwoPartFallsBackToPersonalChannel(testCase)
            name = testCase.MissingRepo;
            srcDir = createTestSourcePackage(testCase.SourceDir, name);
            outDir = fullfile(testCase.SourceDir, 'out');
            mkdir(outDir);
            evalc('mip.bundle(srcDir, ''--output'', outDir, ''--arch'', ''any'')');
            mhl = dir(fullfile(outDir, '*.mhl'));
            writeChannelIndex(testCase.TestRoot, 'mip-org/mip-org', ...
                {struct('name', name, 'mhl_url', fullfile(outDir, mhl(1).name))});

            out = evalc('mip.install([''mip-org/'' name])');

            testCase.verifySubstring(out, ...
                sprintf('github.com/mip-org/%s does not publish a mip package.', name));
            testCase.verifySubstring(out, 'from the personal channel mip-org/mip-org instead');
            testCase.verifyEqual(mip.state.list_installed_packages(), ...
                {['gh/mip-org/mip-org/' name]});
        end

        function testFallbackNotFoundNamesBothLocations(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/mip-org', {});
            try
                evalc('mip.install([''mip-org/'' testCase.MissingRepo])');
                testCase.verifyFail('expected an error');
            catch ME
                testCase.verifyEqual(ME.identifier, 'mip:packageNotFound');
                testCase.verifySubstring(ME.message, ['github.com/mip-org/' testCase.MissingRepo]);
                testCase.verifySubstring(ME.message, 'mip-org/mip-org');
            end
        end

        function testExplicitRepoFormHasNoFallback(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/mip-org', {testCase.MissingRepo});
            url = ['https://github.com/mip-org/' testCase.MissingRepo];
            testCase.verifyError(@() quietly(@() mip.install(url)), 'mip:repo:notPublished');
        end

    end
end


function quietly(fn)
% Call fn with its command-window output suppressed.
    evalc('fn()');
end
