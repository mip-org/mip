classdef TestExtractMhl < matlab.unittest.TestCase
%TESTEXTRACTMHL   Tests for mip.channel.extract_mhl and
% mip.channel.assert_mhl_safe.
%
% These tests build ZIP archives on the fly by hand-writing the
% bytes in pure MATLAB, so the fixtures are fully cross-platform.

    properties
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.TestRoot = [tempname '_extract_mhl_test'];
            mkdir(testCase.TestRoot);
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
        end
    end

    methods (Test)

        function testValidArchiveExtracts(testCase)
            % Happy path: a well-formed archive with mip.json and a source
            % file extracts successfully, and both files land under destDir.
            zipPath = fullfile(testCase.TestRoot, 'good.mhl');
            makeZip(zipPath, { ...
                'mip.json', '{"name":"pkg","version":"1.0.0"}'; ...
                'src/foo.m', 'function foo, end'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            mip.channel.extract_mhl(zipPath, destDir);

            testCase.verifyTrue(exist(fullfile(destDir, 'mip.json'), 'file') > 0);
            testCase.verifyTrue(exist(fullfile(destDir, 'src', 'foo.m'), 'file') > 0);
        end

        function testTraversalEntryRejected(testCase)
            % An entry that starts with "../" escapes destDir by one level.
            % The validator must reject it BEFORE unzip runs, so neither
            % destDir nor the escaped file is ever created.
            zipPath = fullfile(testCase.TestRoot, 'evil.mhl');
            makeZip(zipPath, { ...
                'mip.json', '{"name":"pkg","version":"1.0.0"}'; ...
                '../escaped.txt', 'pwned'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
            testCase.verifyFalse(exist(destDir, 'dir') > 0, ...
                'destDir must not exist after pre-extraction rejection');
            testCase.verifyFalse(exist(fullfile(testCase.TestRoot, 'escaped.txt'), 'file') > 0, ...
                'escaped file must not have been written');
        end

        function testDeepTraversalEntryRejected(testCase)
            % An entry that uses several ".." components to climb out of
            % the root must also be rejected. This guards against attackers
            % obscuring the traversal behind plausible-looking subdirs.
            zipPath = fullfile(testCase.TestRoot, 'deep.mhl');
            makeZip(zipPath, { ...
                'mip.json', '{"name":"pkg","version":"1.0.0"}'; ...
                'a/b/../../../escaped.txt', 'pwned'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
        end

        function testAbsolutePathRejected(testCase)
            % An entry with a leading "/" is an absolute path on POSIX and
            % would overwrite files anywhere the MATLAB process can write.
            zipPath = fullfile(testCase.TestRoot, 'abs.mhl');
            makeZip(zipPath, { ...
                'mip.json', '{"name":"pkg","version":"1.0.0"}'; ...
                '/etc/passwd', 'x'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
        end

        function testDriveLetterRejected(testCase)
            % On Windows, an entry like "C:/..." is an absolute path.
            % Reject regardless of current platform so archives built on
            % Windows cannot attack users on other OSes and vice versa.
            zipPath = fullfile(testCase.TestRoot, 'drive.mhl');
            makeZip(zipPath, { ...
                'mip.json', '{"name":"pkg","version":"1.0.0"}'; ...
                'C:/Windows/evil.txt', 'x'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
        end

        function testBackslashTraversalRejected(testCase)
            % The ZIP spec mandates forward slashes, but some writers and
            % some extractors honor backslash as a separator. Treat "\" as
            % equivalent to "/" during validation so a backslash-based
            % traversal can't slip past the check.
            zipPath = fullfile(testCase.TestRoot, 'bs.mhl');
            makeZip(zipPath, { ...
                'mip.json', '{"name":"pkg","version":"1.0.0"}'; ...
                '..\escaped.txt', 'x'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
        end

        function testBenignDotDotAllowed(testCase)
            % "foo/../bar.txt" contains ".." but the resolved path is just
            % "bar.txt" — fully inside the root. The validator must allow
            % this rather than reject every archive containing "..".
            zipPath = fullfile(testCase.TestRoot, 'benign.mhl');
            makeZip(zipPath, { ...
                'mip.json', '{"name":"pkg","version":"1.0.0"}'; ...
                'foo/../bar.txt', 'ok'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            mip.channel.extract_mhl(zipPath, destDir);
            testCase.verifyTrue(exist(fullfile(destDir, 'bar.txt'), 'file') > 0);
        end

        function testMissingMipJsonRejected(testCase)
            % A ZIP with safe entries but no mip.json is not a valid mip
            % package. Verifies the existing invalidPackage check still
            % fires after the new pre-extraction validation.
            zipPath = fullfile(testCase.TestRoot, 'nojson.mhl');
            makeZip(zipPath, {'README.md', 'hi'});

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:invalidPackage');
        end

        function testMismatchedCdAndLocalNameRejected(testCase)
            % Crafted archive whose central directory advertises a safe
            % name ("safe.txt") but whose local file header says
            % "../escaped.txt". MATLAB's unzip() honors the local-header
            % name, so a check that only reads the central directory
            % would be bypassed. The validator must read local headers
            % and reject this before extraction.
            zipPath = fullfile(testCase.TestRoot, 'mismatch.mhl');
            makeMismatchedZip(zipPath, '../escaped.txt', 'safe.txt', 'payload');

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
            testCase.verifyFalse(exist(fullfile(testCase.TestRoot, 'escaped.txt'), 'file') > 0, ...
                'escaped file must not have been written');
        end

        function testSymlinkAbsoluteTargetRejected(testCase)
            % Symlink entry (S_IFLNK in external attrs) whose target is
            % an absolute path. If the extractor materializes the link,
            % a subsequent entry named "link/x" escapes destDir by
            % following the link to /etc/x. Must be rejected.
            zipPath = fullfile(testCase.TestRoot, 'symlink_abs.mhl');
            makeSymlinkZip(zipPath, 'link', '/etc/');

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
        end

        function testSymlinkRelativeEscapingTargetRejected(testCase)
            % Symlink with a relative target that climbs out of destDir
            % ("../../../etc"). The walk of (dirname(link) + target)
            % must detect the escape and refuse.
            zipPath = fullfile(testCase.TestRoot, 'symlink_rel.mhl');
            makeSymlinkZip(zipPath, 'sub/link', '../../../etc');

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(zipPath, destDir), ...
                                 'mip:pathTraversal');
        end

        function testSymlinkBenignRelativeTargetAllowed(testCase)
            % Symlink whose target stays inside destDir
            % ("sub/link" -> "../other"  resolves to "other" at root).
            % Must NOT be rejected — only escaping symlinks are unsafe.
            zipPath = fullfile(testCase.TestRoot, 'symlink_ok.mhl');
            makeZipMixed(zipPath, { ...
                'mip.json',  '{"name":"pkg","version":"1.0.0"}',   uint32(0); ...
                'sub/link',  '../other',                           uint32(hex2dec('A1FF0000'))});

            destDir = fullfile(testCase.TestRoot, 'dest');
            mip.channel.extract_mhl(zipPath, destDir);
            testCase.verifyTrue(exist(fullfile(destDir, 'mip.json'), 'file') > 0);
        end

        function testNonZipRejected(testCase)
            % A file that isn't a ZIP at all should be rejected cleanly by
            % the parser (with mip:invalidPackage) rather than crashing
            % MATLAB's unzip or silently doing nothing.
            txtPath = fullfile(testCase.TestRoot, 'notazip.mhl');
            fid = fopen(txtPath, 'w');
            fwrite(fid, uint8('this is not a zip file'));
            fclose(fid);

            destDir = fullfile(testCase.TestRoot, 'dest');
            testCase.verifyError(@() mip.channel.extract_mhl(txtPath, destDir), ...
                                 'mip:invalidPackage');
        end

    end

end

function makeZip(zipPath, entries)
% Build a stored (uncompressed) ZIP at zipPath. entries is an Nx2 cell
% array of {name, content} pairs; content may be a char row or a uint8
% vector. Names are written identically to both the local file header
% and the central directory.
    writeZip(zipPath, entries, entries, zeros(1, size(entries, 1), 'uint32'));
end

function makeMismatchedZip(zipPath, localName, cdName, content)
% Build a single-entry ZIP where the local file header and central
% directory disagree on the entry name.
    writeZip(zipPath, {localName, content}, {cdName, content}, uint32(0));
end

function makeSymlinkZip(zipPath, name, target)
% Build a single-entry ZIP whose central directory marks the entry as
% a Unix symlink (S_IFLNK = 0xA000 in the high 16 bits of the external
% file attributes). The entry's payload is the symlink target, per
% Unix ZIP convention.
    extAttr = uint32(hex2dec('A1FF0000'));
    writeZip(zipPath, {name, target}, {name, target}, extAttr);
end

function makeZipMixed(zipPath, entries)
% Build a ZIP where each row of entries is {name, content, extAttr}.
% Use extAttr = 0 for regular files and 0xA1FF0000 for Unix symlinks
% (whose content is interpreted as the link target).
    nameContent = entries(:, 1:2);
    extAttrs = uint32([entries{:, 3}]);
    writeZip(zipPath, nameContent, nameContent, extAttrs);
end

function writeZip(zipPath, localEntries, cdEntries, extAttrs)
% Hand-assemble a ZIP file. localEntries / cdEntries are Nx2 cell
% arrays of {name, content}; extAttrs is a uint32 vector of external
% file attribute values (one per CD entry).
    nEntries = size(localEntries, 1);
    assert(nEntries == size(cdEntries, 1), 'entry count mismatch');
    assert(numel(extAttrs) == nEntries, 'extAttrs length mismatch');

    localHeaderOffsets = zeros(1, nEntries, 'uint32');
    bodyBytes = uint8([]);
    cursor = 0;

    for i = 1:nEntries
        [nameBytes, content, crc, sz] = prepEntry(localEntries{i, 1}, localEntries{i, 2});
        lfh = [ ...
            u32(hex2dec('04034b50')), ...
            u16(20), u16(0), u16(0), ...
            u16(0), u16(hex2dec('0021')), ...
            u32(crc), u32(sz), u32(sz), ...
            u16(numel(nameBytes)), u16(0), ...
            nameBytes];
        localHeaderOffsets(i) = uint32(cursor);
        bodyBytes = [bodyBytes, lfh, content]; %#ok<AGROW>
        cursor = cursor + numel(lfh) + numel(content);
    end

    cdBytes = uint8([]);
    for i = 1:nEntries
        [nameBytes, ~, crc, sz] = prepEntry(cdEntries{i, 1}, cdEntries{i, 2});
        cdh = [ ...
            u32(hex2dec('02014b50')), ...
            u16(20), u16(20), ...
            u16(0), u16(0), ...
            u16(0), u16(hex2dec('0021')), ...
            u32(crc), u32(sz), u32(sz), ...
            u16(numel(nameBytes)), u16(0), u16(0), ...
            u16(0), u16(0), u32(extAttrs(i)), ...
            u32(localHeaderOffsets(i)), ...
            nameBytes];
        cdBytes = [cdBytes, cdh]; %#ok<AGROW>
    end

    eocd = [ ...
        u32(hex2dec('06054b50')), ...
        u16(0), u16(0), ...
        u16(nEntries), u16(nEntries), ...
        u32(numel(cdBytes)), u32(cursor), ...
        u16(0)];

    fid = fopen(zipPath, 'w');
    fwrite(fid, [bodyBytes, cdBytes, eocd], 'uint8');
    fclose(fid);
end

function [nameBytes, content, crc, sz] = prepEntry(name, content)
    if ischar(content)
        content = uint8(content);
    end
    nameBytes = uint8(name);
    crc = crc32(content);
    sz  = uint32(numel(content));
end

function crc = crc32(data)
% CRC-32 (IEEE 802.3 / zlib / ZIP). Pure MATLAB, no toolbox dependency.
% Slow for large inputs but fine for test-sized payloads.
    crc = uint32(hex2dec('FFFFFFFF'));
    poly = uint32(hex2dec('EDB88320'));
    for k = 1:numel(data)
        crc = bitxor(crc, uint32(data(k)));
        for j = 1:8
            if bitand(crc, uint32(1))
                crc = bitxor(bitshift(crc, -1), poly);
            else
                crc = bitshift(crc, -1);
            end
        end
    end
    crc = bitxor(crc, uint32(hex2dec('FFFFFFFF')));
end

function b = u16(v), b = typecast(uint16(v), 'uint8'); end
function b = u32(v), b = typecast(uint32(v), 'uint8'); end
