classdef TestFunctionSignatures < matlab.unittest.TestCase
%TESTFUNCTIONSIGNATURES   Tests for mip.state.update_function_signatures.
%
% Verifies that the regenerated functionSignatures.json reflects the
% current installed / loaded / pinned package state. The tests pass an
% isolated resources directory to the helper so they do not touch the
% real installed mip/resources/functionSignatures.json.

    properties
        OrigMipRoot
        TestRoot
        ResourcesDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.ResourcesDir = fullfile(testCase.TestRoot, 'resources');
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

        function testFileIsCreated(testCase)
            mip.state.update_function_signatures(testCase.ResourcesDir);
            jsonPath = fullfile(testCase.ResourcesDir, 'functionSignatures.json');
            testCase.verifyTrue(exist(jsonPath, 'file') == 2);
        end

        function testInstalledPackagesAppearInLoadChoices(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');

            mip.state.update_function_signatures(testCase.ResourcesDir);

            content = readJson(testCase.ResourcesDir);
            loadSig = extractSignature(content, 'load');
            testCase.verifyNotEmpty(loadSig, ...
                'load signature should be present in JSON');
            testCase.verifyTrue(contains(loadSig, '''alpha'''), ...
                'alpha should appear in load choices');
            testCase.verifyTrue(contains(loadSig, '''beta'''), ...
                'beta should appear in load choices');
        end

        function testOnlyLoadedPackagesAppearInUnloadChoices(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/alpha');

            mip.state.update_function_signatures(testCase.ResourcesDir);

            content = readJson(testCase.ResourcesDir);
            unloadSig = extractSignature(content, 'unload');
            testCase.verifyTrue(contains(unloadSig, '''alpha'''));
            testCase.verifyFalse(contains(unloadSig, '''beta'''), ...
                'unload choices should not contain unloaded packages');
        end

        function testOnlyPinnedPackagesAppearInUnpinChoices(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            mip.state.add_pinned('gh/mip-org/core/alpha');

            mip.state.update_function_signatures(testCase.ResourcesDir);

            content = readJson(testCase.ResourcesDir);
            unpinSig = extractSignature(content, 'unpin');
            testCase.verifyTrue(contains(unpinSig, '''alpha'''));
            testCase.verifyFalse(contains(unpinSig, '''beta'''));
        end

        function testEmptyStateProducesValidFile(testCase)
            mip.state.update_function_signatures(testCase.ResourcesDir);
            content = readJson(testCase.ResourcesDir);
            % All subcommands should still be listed even with no packages
            for cmd = {'install','load','unload','list','version','help'}
                testCase.verifyTrue(contains(content, sprintf('''%s''', cmd{1})), ...
                    sprintf('Subcommand ''%s'' missing from empty-state JSON', cmd{1}));
            end
        end

        function testRegenerationReflectsNewPackages(testCase)
            mip.state.update_function_signatures(testCase.ResourcesDir);
            first = readJson(testCase.ResourcesDir);
            testCase.verifyFalse(contains(first, '''newpkg'''));

            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'newpkg');
            mip.state.update_function_signatures(testCase.ResourcesDir);
            second = readJson(testCase.ResourcesDir);
            testCase.verifyTrue(contains(second, '''newpkg'''));
        end

        function testMipItselfExcludedFromLoadAndUnloadChoices(testCase)
            % gh/mip-org/core/mip is always loaded+sticky, so offering
            % it as a load/unload target would only be a no-op.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/mip');
            mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/alpha');

            mip.state.update_function_signatures(testCase.ResourcesDir);

            content = readJson(testCase.ResourcesDir);
            loadSig   = extractSignature(content, 'load');
            unloadSig = extractSignature(content, 'unload');

            testCase.verifyFalse(contains(loadSig, '''mip'''), ...
                'load choices must exclude mip itself');
            testCase.verifyFalse(contains(unloadSig, '''mip'''), ...
                'unload choices must exclude mip itself');
            testCase.verifyTrue(contains(loadSig, '''alpha'''));
            testCase.verifyTrue(contains(unloadSig, '''alpha'''));
        end

        function testOtherChannelMipStillAppearsInLoadChoices(testCase)
            % Only gh/mip-org/core/mip is excluded; a package named 'mip'
            % on a different channel must still appear.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            createTestPackage(testCase.TestRoot, 'other', 'channel', 'mip');

            mip.state.update_function_signatures(testCase.ResourcesDir);

            content = readJson(testCase.ResourcesDir);
            loadSig = extractSignature(content, 'load');
            testCase.verifyTrue(contains(loadSig, '''mip'''), ...
                'mip from a non-core channel should still appear in load choices');
        end

        function testMipItselfIncludedInUninstallAndUpdateChoices(testCase)
            % `mip uninstall mip` and `mip update mip` are valid, so mip
            % should still appear in those completion choices.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');

            mip.state.update_function_signatures(testCase.ResourcesDir);

            content = readJson(testCase.ResourcesDir);
            uninstallSig = extractSignature(content, 'uninstall');
            updateSig    = extractSignature(content, 'update');

            testCase.verifyTrue(contains(uninstallSig, '''mip'''));
            testCase.verifyTrue(contains(updateSig, '''mip'''));
        end

        function testDuplicateBareNamesAreDeduplicated(testCase)
            % Same bare name on two different channels should appear once
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkg');
            createTestPackage(testCase.TestRoot, 'other', 'channel', 'pkg');

            mip.state.update_function_signatures(testCase.ResourcesDir);
            content = readJson(testCase.ResourcesDir);
            loadSig = extractSignature(content, 'load');
            occurrences = length(strfind(loadSig, '''pkg'''));
            testCase.verifyEqual(occurrences, 1, ...
                'Duplicate bare name should appear once in load choices');
        end

    end
end


function content = readJson(resourcesDir)
    fid = fopen(fullfile(resourcesDir, 'functionSignatures.json'), 'r');
    content = fread(fid, inf, '*char')';
    fclose(fid);
end


function sig = extractSignature(content, cmd)
% Return the substring of the JSON containing the "mip" signature whose
% command-choice is the given subcommand. Returns '' if not found.
    marker = sprintf('"choices={''%s''}"', cmd);
    markerIdx = strfind(content, marker);
    if isempty(markerIdx)
        sig = '';
        return
    end
    % Find the enclosing {...} for this signature by walking back to the
    % preceding '"mip":' and forward to the matching closing brace.
    startIdx = markerIdx(1);
    mipIdx = strfind(content(1:startIdx), '"mip":');
    sigStart = mipIdx(end) + length('"mip":');
    % Skip whitespace to the opening '{'
    while sigStart <= length(content) && content(sigStart) ~= '{'
        sigStart = sigStart + 1;
    end
    % Walk forward tracking brace depth
    depth = 0;
    sigEnd = sigStart;
    while sigEnd <= length(content)
        c = content(sigEnd);
        if c == '{'
            depth = depth + 1;
        elseif c == '}'
            depth = depth - 1;
            if depth == 0
                break
            end
        end
        sigEnd = sigEnd + 1;
    end
    sig = content(sigStart:sigEnd);
end
