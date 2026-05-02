classdef TestPinPackage < matlab.unittest.TestCase
%TESTPINPACKAGE   Tests for mip.pin, mip.unpin, and pinned package behavior.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_pin_test'];
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

        %% --- Pin basics ---

        function testPin_AddsToList(testCase)
            % Pinning by FQN should add the package to the pinned list
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testPin_BareName(testCase)
            % Pinning by bare name should resolve to the FQN and pin it
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('alpha');
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testPin_AlreadyPinned(testCase)
            % Pinning an already-pinned package should print a message, not error
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            output = evalc('mip.pin(''mip-org/core/alpha'')');
            testCase.verifyTrue(contains(output, 'already pinned'));
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testPin_NotInstalled(testCase)
            % Pinning a package that is not installed should error
            testCase.verifyError(@() mip.pin('nonexistent'), ...
                'mip:pin:notInstalled');
        end

        function testPin_MultiplePackages(testCase)
            % Multiple packages can be pinned in a single call
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            mip.pin('mip-org/core/alpha', 'mip-org/core/beta');
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/beta'));
        end

        %% --- Unpin basics ---

        function testUnpin_RemovesFromList(testCase)
            % Unpinning should remove the package from the pinned list
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
            mip.unpin('mip-org/core/alpha');
            testCase.verifyFalse(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testUnpin_NotPinned(testCase)
            % Unpinning a package that is not pinned should print a message, not error
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            output = evalc('mip.unpin(''mip-org/core/alpha'')');
            testCase.verifyTrue(contains(output, 'not pinned'));
        end

        function testUnpin_NotInstalled(testCase)
            % Unpinning a package that is not installed should error
            testCase.verifyError(@() mip.unpin('nonexistent'), ...
                'mip:unpin:notInstalled');
        end

        %% --- Pinned state persistence ---

        function testPinned_PersistsToFile(testCase)
            % Pinned state should be written to pinned.txt for persistence
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');

            pinnedFile = fullfile(testCase.TestRoot, 'packages', 'pinned.txt');
            testCase.verifyTrue(exist(pinnedFile, 'file') > 0);

            content = fileread(pinnedFile);
            testCase.verifyTrue(contains(content, 'mip-org/core/alpha'));
        end

        %% --- List shows pinned marker ---

        function testList_ShowsPinnedMarker(testCase)
            % mip list should show [pinned] next to pinned packages
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            output = evalc('mip.list()');
            testCase.verifyTrue(contains(output, '[pinned]'));
        end

        function testList_NoPinnedMarkerWhenUnpinned(testCase)
            % mip list should not show [pinned] for unpinned packages
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            output = evalc('mip.list()');
            testCase.verifyFalse(contains(output, '[pinned]'));
        end

        %% --- Uninstall removes pin ---

        function testUninstall_RemovesPin(testCase)
            % Uninstalling a pinned package should also remove the pin
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.state.add_directly_installed('mip-org/core/alpha');
            mip.pin('mip-org/core/alpha');
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));

            mip.uninstall('mip-org/core/alpha');
            testCase.verifyFalse(mip.state.is_pinned('mip-org/core/alpha'));
        end

        %% --- Update --all skips pinned ---

        function testUpdateAll_SkipsPinned(testCase)
            % mip update --all should skip pinned packages
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha', ...
                'version', '1.0.0');
            mip.state.add_directly_installed('mip-org/core/alpha');
            mip.pin('mip-org/core/alpha');

            output = evalc('mip.update(''--all'')');
            testCase.verifyTrue(contains(output, 'Skipping pinned package'));
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
            testCase.verifyTrue(contains(output, 'All packages are pinned'));
        end

        function testUpdateAllForce_StillSkipsPinned(testCase)
            % mip update --all --force should still skip pinned packages.
            % --force does not override the pin.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha', ...
                'version', '1.0.0');
            mip.state.add_directly_installed('mip-org/core/alpha');
            mip.pin('mip-org/core/alpha');

            output = evalc('mip.update(''--all'', ''--force'')');
            testCase.verifyTrue(contains(output, 'Skipping pinned package'));
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
            testCase.verifyTrue(contains(output, 'All packages are pinned'));
            % Pin is preserved
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
        end

        %% --- Named update skips pinned with a message ---

        function testUpdateNamed_PinnedSkipped(testCase)
            % mip update <pkg> on a pinned package prints a skip message
            % and returns without error. The pin is preserved.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            output = evalc('mip.update(''mip-org/core/alpha'')');
            testCase.verifyTrue(contains(output, 'Skipping pinned package'));
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testUpdateNamed_PinnedBareNameSkipped(testCase)
            % mip update <bare> on a pinned package skips it after resolving.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            output = evalc('mip.update(''alpha'')');
            testCase.verifyTrue(contains(output, 'Skipping pinned package'));
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
        end

        function testUpdateNamed_PinnedForceSkipped(testCase)
            % --force does not override the pin on a named update.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            output = evalc('mip.update(''--force'', ''mip-org/core/alpha'')');
            testCase.verifyTrue(contains(output, 'Skipping pinned package'));
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testUpdateNamed_PinnedSkipMessageMentionsUnpin(testCase)
            % Skip message should tell the user how to unpin.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            mip.pin('mip-org/core/alpha');
            output = evalc('mip.update(''mip-org/core/alpha'')');
            testCase.verifyTrue(contains(output, 'unpin'));
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
        end

        function testUpdateNamed_AllPinnedSkippedReturnsCleanly(testCase)
            % If every explicit package is pinned, all are skipped and
            % the call returns without error.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'beta');
            mip.pin('mip-org/core/alpha');
            mip.pin('mip-org/core/beta');
            output = evalc('mip.update(''mip-org/core/alpha'', ''mip-org/core/beta'')');
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
            testCase.verifyTrue(contains(output, 'mip-org/core/beta'));
            testCase.verifyEqual(length(strfind(output, 'Skipping pinned package')), 2);
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/beta'));
        end

        function testUpdateNamed_PreservesArgumentOrderInterleaved(testCase)
            % Mixed pinned and unpinned packages: pin-skip messages must
            % appear at their argument-order slot, interleaved with the
            % unpinned packages' update output -- not batched at the top.
            % Uses local installs without source_path so the unpinned
            % packages reach the "no local source" skip line, which is
            % deterministic without network access.
            createTestPackage(testCase.TestRoot, '', '', 'alpha', 'type', 'local');
            createTestPackage(testCase.TestRoot, '', '', 'beta',  'type', 'local');
            createTestPackage(testCase.TestRoot, '', '', 'gamma', 'type', 'local');
            createTestPackage(testCase.TestRoot, '', '', 'delta', 'type', 'local');
            mip.pin('local/beta');
            mip.pin('local/delta');

            output = evalc(['mip.update(''local/alpha'', ''local/beta'', ' ...
                            '''local/gamma'', ''local/delta'')']);

            posAlpha = strfind(output, 'Skipping "local/alpha":');
            posBeta  = strfind(output, 'Skipping pinned package "local/beta"');
            posGamma = strfind(output, 'Skipping "local/gamma":');
            posDelta = strfind(output, 'Skipping pinned package "local/delta"');

            testCase.verifyNotEmpty(posAlpha, 'no-source skip line for alpha missing');
            testCase.verifyNotEmpty(posBeta,  'pin-skip line for beta missing');
            testCase.verifyNotEmpty(posGamma, 'no-source skip line for gamma missing');
            testCase.verifyNotEmpty(posDelta, 'pin-skip line for delta missing');

            testCase.verifyTrue(posAlpha(1) < posBeta(1),  'alpha must precede beta');
            testCase.verifyTrue(posBeta(1)  < posGamma(1), 'beta must precede gamma');
            testCase.verifyTrue(posGamma(1) < posDelta(1), 'gamma must precede delta');
        end

        %% --- --deps drops pinned deps ---

        function testUpdateDeps_PinnedDependencyIsSkipped(testCase)
            % mip update --deps X where X has a pinned dependency Y:
            % Y is dropped from the expansion with a message; X still updates.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'gamma', ...
                'dependencies', {'mip-org/core/alpha'});
            mip.pin('mip-org/core/alpha');

            output = evalc('try; mip.update(''--deps'', ''mip-org/core/gamma''); catch ME; disp(ME.message); end');
            testCase.verifyTrue(contains(output, 'Skipping pinned dependency'));
            testCase.verifyTrue(contains(output, 'mip-org/core/alpha'));
            % Pin is preserved
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testUpdateDeps_PinnedExplicitSkipped(testCase)
            % mip update --deps X where X itself is pinned: X is skipped
            % with the same "Skipping pinned package" message as the
            % non-deps path. With no other named packages, the call
            % returns without error.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'alpha');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'gamma', ...
                'dependencies', {'mip-org/core/alpha'});
            mip.pin('mip-org/core/gamma');
            output = evalc('mip.update(''--deps'', ''mip-org/core/gamma'')');
            testCase.verifyTrue(contains(output, 'Skipping pinned package'));
            testCase.verifyTrue(contains(output, 'mip-org/core/gamma'));
            testCase.verifyTrue(mip.state.is_pinned('mip-org/core/gamma'));
        end

        %% --- State helper edge cases ---

        function testIsPinned_FalseWhenEmpty(testCase)
            % is_pinned should return false when no packages are pinned
            testCase.verifyFalse(mip.state.is_pinned('mip-org/core/alpha'));
        end

        function testGetPinned_EmptyByDefault(testCase)
            % get_pinned should return an empty cell array by default
            testCase.verifyEmpty(mip.state.get_pinned());
        end

        function testRemovePinned_NoErrorWhenNotPinned(testCase)
            % remove_pinned should not error when the package is not in the list
            mip.state.remove_pinned('mip-org/core/alpha');
            testCase.verifyFalse(mip.state.is_pinned('mip-org/core/alpha'));
        end

    end
end
