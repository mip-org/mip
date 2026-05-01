classdef TestDownloadMhl < matlab.unittest.TestCase
%TESTDOWNLOADMHL   Tests for mip.channel.download_mhl.

    properties
        TempDir
        SrcFile
        DestDir
    end

    methods (TestMethodSetup)
        function setup(testCase)
            testCase.TempDir = [tempname '_dlmhl_test'];
            mkdir(testCase.TempDir);
            testCase.SrcFile = fullfile(testCase.TempDir, 'pkg.mhl');
            fid = fopen(testCase.SrcFile, 'w');
            fwrite(fid, uint8('mip test payload'));
            fclose(fid);
            testCase.DestDir = fullfile(testCase.TempDir, 'dl');
        end
    end

    methods (TestMethodTeardown)
        function teardown(testCase)
            if exist(testCase.TempDir, 'dir')
                rmdir(testCase.TempDir, 's');
            end
        end
    end

    methods (Test)

        function testMatchingDigest_Succeeds(testCase)
            % Happy path: passing the correct digest lets the download
            % complete and leaves the file in place.
            actualSha = mip.channel.sha256(testCase.SrcFile);
            testCase.assumeNotEmpty(actualSha, 'JVM unavailable — skipping');
            localPath = mip.channel.download_mhl( ...
                testCase.SrcFile, testCase.DestDir, actualSha);
            testCase.verifyTrue(exist(localPath, 'file') > 0);
        end

        function testMismatchedDigest_SkipsVerification(testCase)
            % SHA-256 verification is currently disabled (see
            % mip-org/mip#201) because channel publishing isn't atomic
            % and the index/asset can briefly disagree. A wrong digest
            % must therefore NOT error — the download succeeds and the
            % file is kept. Re-flip to verifyError('mip:digestMismatch')
            % once publishing is made atomic.
            actualSha = mip.channel.sha256(testCase.SrcFile);
            testCase.assumeNotEmpty(actualSha, 'JVM unavailable — skipping');
            wrongSha = repmat('0', 1, 64);
            localPath = mip.channel.download_mhl( ...
                testCase.SrcFile, testCase.DestDir, wrongSha);
            testCase.verifyTrue(exist(localPath, 'file') > 0);
        end

        function testEmptyDigest_SkipsVerification(testCase)
            % Empty string means "no digest available" (e.g. channel
            % index omitted mhl_sha256): download must still succeed.
            localPath = mip.channel.download_mhl( ...
                testCase.SrcFile, testCase.DestDir, '');
            testCase.verifyTrue(exist(localPath, 'file') > 0);
        end

        function testNoDigestArg_SkipsVerification(testCase)
            % Legacy two-arg call sites (pre-SHA-256 feature) must keep
            % working without modification.
            localPath = mip.channel.download_mhl( ...
                testCase.SrcFile, testCase.DestDir);
            testCase.verifyTrue(exist(localPath, 'file') > 0);
        end

        function testHttpUrl_Rejected(testCase)
            % Plain http:// URLs are refused: mhl_url comes from a
            % third-party-controllable channel index, and the unpacked
            % .mhl is loaded as code, so a network attacker swapping the
            % payload would get persistent code execution. See #229.
            testCase.verifyError( ...
                @() mip.channel.download_mhl( ...
                    'http://example.invalid/pkg.mhl', testCase.DestDir), ...
                'mip:downloadMhl:requireHttps');
        end

    end
end
