classdef TestFetchIndexCacheRemote < matlab.unittest.TestCase
%TESTFETCHINDEXCACHEREMOTE   Network-required tests for the channel index
%   cache. These tests exercise the round trip (download + write cache,
%   stale invalidation, force refresh, failed fetch handling).
%
%   Skipped in run_tests() when MIP_SKIP_REMOTE is set.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_cache_remote_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
        end
    end

    methods (Test)

        function testFreshFetchWritesCache(testCase)
            % After a successful download, the cache file should exist with
            % current-time mtime and be valid JSON.
            channel = 'mip-org/test-channel1';
            cacheFile = fullfile(testCase.TestRoot, 'cache', 'index', ...
                'mip-org', 'test-channel1.json');

            testCase.verifyFalse(isfile(cacheFile));
            mip.channel.fetch_index(channel);
            testCase.verifyTrue(isfile(cacheFile), ...
                'Successful fetch should write a cache file');

            cached = jsondecode(fileread(cacheFile));
            testCase.verifyTrue(isfield(cached, 'packages'));
        end

        function testForceRefreshRewritesCache(testCase)
            % Pre-populate cache with a sentinel; forceRefresh=true should
            % overwrite it with the real channel index.
            channel = 'mip-org/test-channel1';
            cacheFile = writeSentinelCache(testCase.TestRoot, channel, 'sentinel-not-served');

            index = mip.channel.fetch_index(channel, true);

            % Result should not be the sentinel.
            names = cellfun(@(p) p.name, index.packages, 'UniformOutput', false);
            testCase.verifyFalse(any(strcmp(names, 'sentinel-not-served')), ...
                'forceRefresh should bypass the cached sentinel entry');

            % Cache file should have been overwritten.
            cached = jsondecode(fileread(cacheFile));
            pkgs = cached.packages;
            if ~iscell(pkgs)
                pkgs = num2cell(pkgs);
            end
            cachedNames = cellfun(@(p) p.name, pkgs, 'UniformOutput', false);
            testCase.verifyFalse(any(strcmp(cachedNames, 'sentinel-not-served')), ...
                'Cache file should have been overwritten with the real index');
        end

        function testStaleCacheTriggersRefetch(testCase)
            % A cache entry older than the TTL should be ignored.
            channel = 'mip-org/test-channel1';
            cacheFile = writeSentinelCache(testCase.TestRoot, channel, 'stale-sentinel');

            % Backdate the cache file.
            setFileMtime(cacheFile, datetime('now') - seconds(60));

            index = mip.channel.fetch_index(channel);
            names = cellfun(@(p) p.name, index.packages, 'UniformOutput', false);
            testCase.verifyFalse(any(strcmp(names, 'stale-sentinel')), ...
                'Stale cache should be re-downloaded, not served');
        end

        function testFailedFetchDoesNotWriteCache(testCase)
            % A non-existent channel triggers indexFetchFailed and must not
            % write a cache file.
            channel = 'mip-org/this-channel-does-not-exist-xyz123';
            cacheFile = fullfile(testCase.TestRoot, 'cache', 'index', ...
                'mip-org', 'this-channel-does-not-exist-xyz123.json');

            testCase.verifyError(@() mip.channel.fetch_index(channel), ...
                'mip:indexFetchFailed');
            testCase.verifyFalse(isfile(cacheFile), ...
                'Failed fetch must not leave a cache file behind');
        end

        function testAvailForcesRefresh(testCase)
            % mip avail should bypass the cache: a sentinel pre-populated in
            % cache must be overwritten by the real channel after avail runs.
            channel = 'mip-org/test-channel1';
            cacheFile = writeSentinelCache(testCase.TestRoot, channel, 'avail-sentinel');

            evalc('mip.avail(''--channel'', ''mip-org/test-channel1'')');

            cached = jsondecode(fileread(cacheFile));
            pkgs = cached.packages;
            if ~iscell(pkgs)
                pkgs = num2cell(pkgs);
            end
            cachedNames = cellfun(@(p) p.name, pkgs, 'UniformOutput', false);
            testCase.verifyFalse(any(strcmp(cachedNames, 'avail-sentinel')), ...
                'mip avail should re-download and overwrite the cache');
        end

    end
end


function cacheFile = writeSentinelCache(rootDir, channel, sentinelName)
parts = strsplit(channel, '/');
chOwner = parts{1};
chName  = parts{2};

cacheDir = fullfile(rootDir, 'cache', 'index', chOwner);
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
cacheFile = fullfile(cacheDir, [chName '.json']);

pkg = struct( ...
    'name', sentinelName, ...
    'architecture', 'any', ...
    'version', '1.0.0', ...
    'mhl_url', 'https://example.invalid/sentinel.mhl', ...
    'dependencies', {{}});
indexStruct = struct('packages', {{pkg}});

fid = fopen(cacheFile, 'w');
fwrite(fid, jsonencode(indexStruct), 'char');
fclose(fid);
end


function setFileMtime(filePath, dt)
ts = datestr(dt, 'yyyymmddHHMM.SS'); %#ok<DATST>
if ispc
    % PowerShell fallback for Windows.
    cmd = sprintf('powershell -Command "(Get-Item ''%s'').LastWriteTime = [datetime]''%s''"', ...
        filePath, datestr(dt, 'yyyy-mm-dd HH:MM:SS')); %#ok<DATST>
    [status, msg] = system(cmd);
else
    [status, msg] = system(sprintf('touch -t %s "%s"', ts, filePath));
end
if status ~= 0
    error('setFileMtime:touchFailed', 'touch failed: %s', msg);
end
end
