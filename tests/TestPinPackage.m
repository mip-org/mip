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
