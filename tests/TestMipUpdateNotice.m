classdef TestMipUpdateNotice < matlab.unittest.TestCase
%TESTMIPUPDATENOTICE   Self-update notice when loading the core channel index.
%   Covers mip.channel.mip_update_message (notice composition, including the
%   optional mip_compatibility_floor index field), mip.channel.check_mip_update
%   (printing + once-per-command suppression), and the fetch_index wiring
%   (the check applies only to the mip-org/core channel).

    properties
        OrigMipRoot
        OrigNoticeShown
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigNoticeShown = getappdata(0, 'MIP_UPDATE_NOTICE_SHOWN');
            testCase.TestRoot = [tempname '_mip_notice_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            mip.state.key_value_set('MIP_UPDATE_NOTICE_SHOWN', '');
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            setappdata(0, 'MIP_UPDATE_NOTICE_SHOWN', testCase.OrigNoticeShown);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
        end
    end

    methods (Test)

        % ---- mip_update_message: latest-version suggestion ----

        function testNewerVersionSuggestsUpdate(testCase)
            index = makeIndex({mipEntry('1.2.0')});
            msg = mip.channel.mip_update_message(index, '1.1.0');
            testCase.verifySubstring(msg, '1.2.0');
            testCase.verifySubstring(msg, '1.1.0');
            testCase.verifySubstring(msg, 'mip update mip');
            testCase.verifyEmpty(strfind(msg, 'required'));
        end

        function testUpToDateNoMessage(testCase)
            index = makeIndex({mipEntry('1.2.0')});
            msg = mip.channel.mip_update_message(index, '1.2.0');
            testCase.verifyEmpty(msg);
        end

        function testInstalledNewerNoMessage(testCase)
            index = makeIndex({mipEntry('1.2.0')});
            msg = mip.channel.mip_update_message(index, '1.3.0');
            testCase.verifyEmpty(msg);
        end

        function testNonNumericInstalledNoMessage(testCase)
            % A source checkout ('unspecified') or branch install ('main')
            % has no meaningful ordering against numeric releases.
            index = makeIndex({mipEntry('99.0.0')});
            index.mip_compatibility_floor = '99.0.0';
            testCase.verifyEmpty(mip.channel.mip_update_message(index, 'main'));
            testCase.verifyEmpty(mip.channel.mip_update_message(index, 'unspecified'));
            testCase.verifyEmpty(mip.channel.mip_update_message(index, ''));
        end

        function testNoMipEntryNoMessage(testCase)
            index = makeIndex({pkgEntry('chebfun', '5.0.0')});
            msg = mip.channel.mip_update_message(index, '1.0.0');
            testCase.verifyEmpty(msg);
        end

        function testNonNumericIndexVersionsIgnored(testCase)
            % A branch release of mip (e.g. 'main') never triggers the notice.
            index = makeIndex({mipEntry('main')});
            msg = mip.channel.mip_update_message(index, '1.0.0');
            testCase.verifyEmpty(msg);
        end

        function testHighestNumericVersionWins(testCase)
            % Numeric comparison, not lexical: 1.10.0 > 1.9.0.
            index = makeIndex({mipEntry('1.9.0'), mipEntry('1.10.0'), mipEntry('main')});
            msg = mip.channel.mip_update_message(index, '1.9.5');
            testCase.verifySubstring(msg, '1.10.0');
        end

        function testNameEquivalenceMatchesMip(testCase)
            % The identity check uses name equivalence (case-insensitive).
            index = makeIndex({pkgEntry('MIP', '2.0.0')});
            msg = mip.channel.mip_update_message(index, '1.0.0');
            testCase.verifySubstring(msg, '2.0.0');
        end

        function testStructArrayPackagesHandled(testCase)
            % index.packages may arrive as a struct array rather than a cell.
            index = struct('packages', ...
                struct('name', 'mip', 'version', '3.0.0', 'architecture', 'any'));
            msg = mip.channel.mip_update_message(index, '1.0.0');
            testCase.verifySubstring(msg, '3.0.0');
        end

        % ---- mip_update_message: mip_compatibility_floor ----

        function testFloorUnsatisfiedSaysRequired(testCase)
            index = makeIndex({mipEntry('1.2.0')});
            index.mip_compatibility_floor = '1.2.0';
            msg = mip.channel.mip_update_message(index, '1.1.0');
            testCase.verifySubstring(msg, 'required');
            testCase.verifySubstring(msg, '1.2.0');
            testCase.verifySubstring(msg, '1.1.0');
            testCase.verifySubstring(msg, 'mip update mip');
        end

        function testFloorSatisfiedFallsBackToSuggestion(testCase)
            index = makeIndex({mipEntry('1.3.0')});
            index.mip_compatibility_floor = '1.1.0';
            msg = mip.channel.mip_update_message(index, '1.2.0');
            testCase.verifySubstring(msg, '1.3.0');
            testCase.verifyEmpty(strfind(msg, 'required'));
        end

        function testFloorWithoutMipEntryStillRequired(testCase)
            % mip_compatibility_floor applies even if the index publishes no mip entry.
            index = makeIndex({pkgEntry('chebfun', '5.0.0')});
            index.mip_compatibility_floor = '2.0.0';
            msg = mip.channel.mip_update_message(index, '1.0.0');
            testCase.verifySubstring(msg, 'required');
        end

        function testNonNumericFloorIgnored(testCase)
            index = makeIndex({mipEntry('1.0.0')});
            index.mip_compatibility_floor = 'main';
            msg = mip.channel.mip_update_message(index, '1.0.0');
            testCase.verifyEmpty(msg);
        end

        function testEmptyFloorIgnored(testCase)
            index = makeIndex({mipEntry('1.0.0')});
            index.mip_compatibility_floor = '';
            msg = mip.channel.mip_update_message(index, '1.0.0');
            testCase.verifyEmpty(msg);
        end

        % ---- check_mip_update: printing and suppression ----

        function testCheckPrintsNotice(testCase)
            index = makeIndex({mipEntry('9.9.9')});
            output = evalc('mip.channel.check_mip_update(index, ''1.0.0'')');
            testCase.verifySubstring(output, 'mip update mip');
        end

        function testCheckSuppressesRepeatNotice(testCase)
            index = makeIndex({mipEntry('9.9.9')});
            evalc('mip.channel.check_mip_update(index, ''1.0.0'')');
            output = evalc('mip.channel.check_mip_update(index, ''1.0.0'')');
            testCase.verifyEmpty(output);
        end

        function testCheckPrintsAgainAfterMarkerCleared(testCase)
            % mip.m clears the marker at dispatch, so the next command
            % prints the notice again.
            index = makeIndex({mipEntry('9.9.9')});
            evalc('mip.channel.check_mip_update(index, ''1.0.0'')');
            mip.state.key_value_set('MIP_UPDATE_NOTICE_SHOWN', '');
            output = evalc('mip.channel.check_mip_update(index, ''1.0.0'')');
            testCase.verifySubstring(output, 'mip update mip');
        end

        function testCheckPrintsDifferentNotice(testCase)
            % A different notice (e.g. new version published) is not suppressed.
            index1 = makeIndex({mipEntry('9.9.9')});
            index2 = makeIndex({mipEntry('10.0.0')});
            evalc('mip.channel.check_mip_update(index1, ''1.0.0'')');
            output = evalc('mip.channel.check_mip_update(index2, ''1.0.0'')');
            testCase.verifySubstring(output, '10.0.0');
        end

        function testCheckNoNoticeWhenUpToDate(testCase)
            index = makeIndex({mipEntry('1.0.0')});
            output = evalc('mip.channel.check_mip_update(index, ''1.0.0'')');
            testCase.verifyEmpty(output);
        end

        function testCheckNeverErrorsOnMalformedIndex(testCase)
            % Advisory only: malformed input must not break the caller.
            evalc('mip.channel.check_mip_update(struct(), ''1.0.0'')');
            evalc('mip.channel.check_mip_update(struct(''packages'', 42), ''1.0.0'')');
            evalc('mip.channel.check_mip_update([], ''1.0.0'')');
            index = makeIndex({mipEntry('9.9.9')});
            evalc('mip.channel.check_mip_update(index, 42)');
            % Default installed-version path (resolved via mip.version()).
            evalc('mip.channel.check_mip_update(index)');
            testCase.verifyTrue(true);
        end

        % ---- fetch_index wiring ----

        function testFetchIndexNonCoreChannelNoNotice(testCase)
            % The check applies only to mip-org/core: a non-core index with a
            % huge mip version and mip_compatibility_floor prints nothing, regardless
            % of the installed mip version.
            writeCache(testCase.TestRoot, 'mylab/custom', ...
                makeIndex({mipEntry('999999.0.0')}, '999999.0.0'));
            output = evalc('mip.channel.fetch_index(''mylab/custom'')');
            testCase.verifyEmpty(strfind(output, 'mip update mip'));
        end

        function testFetchIndexCoreChannelNoMipEntryNoNotice(testCase)
            writeCache(testCase.TestRoot, 'mip-org/core', ...
                makeIndex({pkgEntry('chebfun', '5.0.0')}));
            output = evalc('mip.channel.fetch_index(''mip-org/core'')');
            testCase.verifyEmpty(strfind(output, 'mip update mip'));
        end

        function testFetchIndexCoreChannelRunsCheck(testCase)
            % The wiring stores the composed notice in the state marker when
            % one applies. With a source-checkout mip (non-numeric version)
            % no notice applies; either way fetch_index must not error and
            % must return the index.
            writeCache(testCase.TestRoot, 'mip-org/core', ...
                makeIndex({mipEntry('999999.0.0')}));
            index = mip.channel.fetch_index('mip-org/core');
            testCase.verifyEqual(index.packages{1}.name, 'mip');
        end

    end
end


function e = pkgEntry(name, version)
e = struct('name', name, 'version', version, 'architecture', 'any', ...
           'mhl_url', 'https://example.invalid/pkg.mhl', ...
           'dependencies', {{}});
end

function e = mipEntry(version)
e = pkgEntry('mip', version);
end

function index = makeIndex(entries, floorVersion)
index = struct('packages', {entries});
if nargin >= 2
    index.mip_compatibility_floor = floorVersion;
end
end

function writeCache(rootDir, channel, index)
% Write a synthetic channel index into the on-disk cache so fetch_index
% serves it without network access.
parts = strsplit(channel, '/');
cacheDir = fullfile(rootDir, 'cache', 'index', parts{1});
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
cacheFile = fullfile(cacheDir, [parts{2} '.json']);
fid = fopen(cacheFile, 'w');
fwrite(fid, jsonencode(index), 'char');
fclose(fid);
end
