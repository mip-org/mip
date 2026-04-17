classdef TestFetchIndexCache < matlab.unittest.TestCase
%TESTFETCHINDEXCACHE   Cache-only tests for mip.channel.fetch_index.
%   These tests do not require network access. They verify that a fresh
%   on-disk cache entry is honored without contacting the network.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_cache_test'];
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

        function testCacheHitReturnsCachedContent(testCase)
            % A fresh cache entry should be served without network access.
            channel = 'mip-org/core';
            cacheFile = writeSentinelCache(testCase.TestRoot, channel, 'sentinel-pkg-xyz');

            index = mip.channel.fetch_index(channel);

            testCase.verifyTrue(isfield(index, 'packages'));
            testCase.verifyEqual(length(index.packages), 1);
            testCase.verifyEqual(index.packages{1}.name, 'sentinel-pkg-xyz');

            % Cache file should still exist (and not have been re-downloaded).
            testCase.verifyTrue(isfile(cacheFile));
        end

        function testCacheHitWithCustomChannel(testCase)
            % The cache path uses org/channel as nested directories.
            channel = 'mylab/custom';
            cacheFile = writeSentinelCache(testCase.TestRoot, channel, 'mylab-sentinel');

            expectedPath = fullfile(testCase.TestRoot, 'cache', 'index', ...
                'mylab', 'custom.json');
            testCase.verifyEqual(cacheFile, expectedPath);

            index = mip.channel.fetch_index(channel);
            testCase.verifyEqual(index.packages{1}.name, 'mylab-sentinel');
        end

        function testEmptyChannelDefaultsToCore(testCase)
            % Passing '' should resolve to the mip-org/core cache entry.
            writeSentinelCache(testCase.TestRoot, 'mip-org/core', 'core-sentinel');

            index = mip.channel.fetch_index('');
            testCase.verifyEqual(index.packages{1}.name, 'core-sentinel');
        end

        function testNormalizesMissingDependencies(testCase)
            % Cached entries lacking a dependencies field are normalized to {}.
            channel = 'mip-org/core';
            cacheDir = fullfile(testCase.TestRoot, 'cache', 'index', 'mip-org');
            mkdir(cacheDir);
            cacheFile = fullfile(cacheDir, 'core.json');

            % Hand-craft JSON without a dependencies field.
            json = '{"packages":[{"name":"nodeps","architecture":"any","version":"1.0.0"}]}';
            fid = fopen(cacheFile, 'w');
            fwrite(fid, json, 'char');
            fclose(fid);

            index = mip.channel.fetch_index(channel);
            testCase.verifyEqual(index.packages{1}.dependencies, {});
        end

    end
end


function cacheFile = writeSentinelCache(rootDir, channel, sentinelName)
% Write a synthetic channel index containing a single sentinel package and
% return the path. The cache file mtime is fresh (current time).
parts = strsplit(channel, '/');
org = parts{1};
chName = parts{2};

cacheDir = fullfile(rootDir, 'cache', 'index', org);
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
