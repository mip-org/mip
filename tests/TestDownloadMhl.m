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

        function testMismatchedDigest_ErrorsAndDeletes(testCase)
            % Tamper-detection path: a wrong digest must raise
            % mip:digestMismatch AND scrub the local copy, so a poisoned
            % archive can't be picked up by a later caller.
            actualSha = mip.channel.sha256(testCase.SrcFile);
            testCase.assumeNotEmpty(actualSha, 'JVM unavailable — skipping');
            wrongSha = repmat('0', 1, 64);
            testCase.verifyError( ...
                @() mip.channel.download_mhl( ...
                    testCase.SrcFile, testCase.DestDir, wrongSha), ...
                'mip:digestMismatch');
            expectedLocal = fullfile(testCase.DestDir, 'pkg.mhl');
            testCase.verifyFalse(exist(expectedLocal, 'file') > 0, ...
                'Local copy should be deleted on digest mismatch');
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

    end
end
