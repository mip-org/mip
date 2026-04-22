classdef TestUpdateBranchOrVersion < matlab.unittest.TestCase
%TESTUPDATEBRANCHORVERSION   Tests that `mip update` preserves non-numeric
%branches or versions (main/master/unspecified) rather than silently
%switching to a newly published numeric release.
%
%   Uses a synthetic channel cache (no network) to simulate a channel
%   that has both a branch ("main") and a numeric release.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_branch_or_version_test'];
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

        function testUpdate_StaysOnMain_WhenNumericExists(testCase)
            % Installed alpha@main with hash abc123. Channel has both
            % alpha@main (hash abc123) and alpha@0.5.0. `mip update`
            % should pick the installed 'main' branch, find no change,
            % and report up-to-date — not switch to 0.5.0.
            fqn = 'mip-org/test-channel-bt/alpha';
            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'test-channel-bt', 'alpha');
            writeInstalledPackage(pkgDir, 'alpha', 'main', 'abc123');
            mip.state.add_directly_installed(fqn);

            writeChannelIndex(testCase.TestRoot, 'mip-org/test-channel-bt', { ...
                makeIndexEntry('alpha', 'main',  'abc123'), ...
                makeIndexEntry('alpha', '0.5.0', 'def456') ...
            });

            output = evalc('mip.update(fqn)');

            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.version, 'main', ...
                'Update must not switch from main to a numeric release.');
            testCase.verifySubstring(output, 'already up to date');
            testCase.verifyEmpty(strfind(output, '0.5.0'), ...
                'Update output should not mention the numeric release.');
        end

        function testUpdate_StaysOnUnspecified_WhenNumericExists(testCase)
            % Same rule applies to 'unspecified'.
            fqn = 'mip-org/test-channel-bt/beta';
            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'test-channel-bt', 'beta');
            writeInstalledPackage(pkgDir, 'beta', 'unspecified', 'abc123');
            mip.state.add_directly_installed(fqn);

            writeChannelIndex(testCase.TestRoot, 'mip-org/test-channel-bt', { ...
                makeIndexEntry('beta', 'unspecified', 'abc123'), ...
                makeIndexEntry('beta', '1.0.0',       'def456') ...
            });

            mip.update(fqn);

            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.version, 'unspecified');
        end

        function testUpdate_MainMissingFromChannel_Errors(testCase)
            % If the installed branch or version no longer exists in the
            % channel, `mip update` should not silently fall through to
            % a numeric version — it should surface an error so the
            % user can decide whether to switch to a different branch or
            % version explicitly.
            fqn = 'mip-org/test-channel-bt/gamma';
            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'test-channel-bt', 'gamma');
            writeInstalledPackage(pkgDir, 'gamma', 'main', 'abc123');
            mip.state.add_directly_installed(fqn);

            writeChannelIndex(testCase.TestRoot, 'mip-org/test-channel-bt', { ...
                makeIndexEntry('gamma', '1.0.0', 'def456') ...
            });

            testCase.verifyError(@() mip.update(fqn), 'mip:update:versionNotInChannel');

            info = mip.config.read_package_json(pkgDir);
            testCase.verifyEqual(info.version, 'main', ...
                'Installed package must not be modified when update errors.');
        end

        function testUpdate_NumericInstalled_StillPicksHighest(testCase)
            % Regression guard: the fix must not affect numeric installs.
            % Installed alpha@1.0.0, channel has 1.0.0, 2.0.0, and main;
            % update should still want to go to 2.0.0.
            fqn = 'mip-org/test-channel-bt/delta';
            pkgDir = fullfile(testCase.TestRoot, 'packages', ...
                'gh', 'mip-org', 'test-channel-bt', 'delta');
            writeInstalledPackage(pkgDir, 'delta', '1.0.0', 'aaa');
            mip.state.add_directly_installed(fqn);

            writeChannelIndex(testCase.TestRoot, 'mip-org/test-channel-bt', { ...
                makeIndexEntry('delta', '1.0.0', 'aaa'), ...
                makeIndexEntry('delta', '2.0.0', 'bbb'), ...
                makeIndexEntry('delta', 'main',  'ccc') ...
            });

            output = evalc('try, mip.update(fqn); catch; end');
            testCase.verifySubstring(output, '1.0.0 -> 2.0.0');
        end

    end
end

function writeInstalledPackage(pkgDir, name, version, commitHash)
% Create a minimal on-disk installed package matching what update.m
% reads via mip.config.read_package_json.
    if ~exist(pkgDir, 'dir')
        mkdir(pkgDir);
    end
    data = struct( ...
        'name', name, ...
        'version', version, ...
        'architecture', 'any', ...
        'install_type', 'test', ...
        'commit_hash', commitHash, ...
        'dependencies', {reshape({}, 0, 1)});
    fid = fopen(fullfile(pkgDir, 'mip.json'), 'w');
    fwrite(fid, jsonencode(data));
    fclose(fid);
end

function entry = makeIndexEntry(name, version, commitHash)
    entry = struct( ...
        'name', name, ...
        'version', version, ...
        'commit_hash', commitHash);
end
