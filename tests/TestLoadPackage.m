classdef TestLoadPackage < matlab.unittest.TestCase
%TESTLOADPACKAGE   Tests for mip.load functionality.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
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

        function testLoadPackage_Basic(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/testpkg'));
        end

        function testLoadPackage_MarkedAsDirectlyLoaded(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue(mip.state.is_directly_loaded('mip-org/core/testpkg'));
        end

        function testLoadPackage_AlreadyLoaded(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            % Loading again should not error
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/testpkg'));
        end

        function testLoadPackage_WithStickyFlag(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg', '--sticky');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/testpkg'));
            testCase.verifyTrue(mip.state.is_sticky('mip-org/core/testpkg'));
        end

        function testLoadPackage_BareName(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('testpkg');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/testpkg'));
        end

        function testLoadPackage_NotInstalled(testCase)
            testCase.verifyError(@() mip.load('nonexistent'), ...
                'mip:packageNotFound');
        end

        function testLoadPackage_WithDependency(testCase)
            % Create dependency package
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            % Create main package that depends on depA
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            mip.load('mip-org/core/mainpkg');
            % Both should be loaded
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/mainpkg'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'));
        end

        function testLoadPackage_DependencyNotDirectlyLoaded(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            mip.load('mip-org/core/mainpkg');
            % depA loaded as dependency, not directly
            testCase.verifyTrue(mip.state.is_directly_loaded('mip-org/core/mainpkg'));
            testCase.verifyFalse(mip.state.is_directly_loaded('mip-org/core/depA'));
        end

        function testLoadPackage_ChainedDependencies(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depB');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA', ...
                'dependencies', {'depB'});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            mip.load('mip-org/core/mainpkg');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/mainpkg'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depB'));
        end

        function testLoadPackage_MipAlwaysLoaded(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mip');
            % Loading 'mip' FQN should print message but not error
            mip.load('mip-org/core/mip');
        end

        function testLoadPackage_CustomChannel(testCase)
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'mypkg');
            mip.load('mylab/custom/mypkg');
            testCase.verifyTrue(mip.state.is_loaded('mylab/custom/mypkg'));
        end

        function testLoadPackage_LocalPackage(testCase)
            createTestPackage(testCase.TestRoot, '', '', 'devpkg', 'type', 'local');
            mip.load('local/devpkg');
            testCase.verifyTrue(mip.state.is_loaded('local/devpkg'));
        end

        function testLoadPackage_AddsToPath(testCase)
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            srcDir = fullfile(pkgDir, 'testpkg');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));
        end

        function testLoadPackage_MultipleDependencies(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depB');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA', 'depB'});
            mip.load('mip-org/core/mainpkg');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depA'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/depB'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/mainpkg'));
        end

        function testLoadPackage_MultiplePackagesAtOnce(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgB');
            mip.load('mip-org/core/pkgA', 'mip-org/core/pkgB');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/pkgA'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/pkgB'));
        end

        function testLoadPackage_MultiplePackagesAllDirectlyLoaded(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgB');
            mip.load('mip-org/core/pkgA', 'mip-org/core/pkgB');
            testCase.verifyTrue(mip.state.is_directly_loaded('mip-org/core/pkgA'));
            testCase.verifyTrue(mip.state.is_directly_loaded('mip-org/core/pkgB'));
        end

        function testLoadPackage_MultiplePackagesWithSticky(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgB');
            mip.load('mip-org/core/pkgA', 'mip-org/core/pkgB', '--sticky');
            testCase.verifyTrue(mip.state.is_sticky('mip-org/core/pkgA'));
            testCase.verifyTrue(mip.state.is_sticky('mip-org/core/pkgB'));
        end

        function testLoadPackage_MultiplePackagesBareNames(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgB');
            mip.load('pkgA', 'pkgB');
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/pkgA'));
            testCase.verifyTrue(mip.state.is_loaded('mip-org/core/pkgB'));
        end

        function testLoadPackage_MissingPathsField_Errors(testCase)
            % A package whose mip.json has no "paths" field cannot be loaded.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'badpkg');
            removePathsField(fullfile(pkgDir, 'mip.json'));
            testCase.verifyError(@() mip.load('mip-org/core/badpkg'), 'mip:loadNotFound');
        end

        function testLoadPackage_MissingPathsField_NotMarkedLoaded(testCase)
            % After a failed load, the package must not be marked as loaded.
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'badpkg');
            removePathsField(fullfile(pkgDir, 'mip.json'));
            try
                mip.load('mip-org/core/badpkg');
            catch
                % expected
            end
            testCase.verifyFalse(mip.state.is_loaded('mip-org/core/badpkg'));
            testCase.verifyFalse(mip.state.is_directly_loaded('mip-org/core/badpkg'));
        end

        %% Direct loads mark the package as directly_installed

        function testLoadPackage_MarksAsDirectlyInstalled(testCase)
            % A direct load should add the package to directly_installed,
            % so it survives an uninstall of any parent that depends on it.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'testpkg');
            mip.load('mip-org/core/testpkg');
            testCase.verifyTrue( ...
                ismember('gh/mip-org/core/testpkg', mip.state.get_directly_installed()));
        end

        function testLoadPackage_TransitiveDepNotMarkedDirectlyInstalled(testCase)
            % A package loaded only as a transitive dependency must not
            % become directly_installed.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            mip.load('mip-org/core/mainpkg');
            testCase.verifyTrue( ...
                ismember('gh/mip-org/core/mainpkg', mip.state.get_directly_installed()));
            testCase.verifyFalse( ...
                ismember('gh/mip-org/core/depA', mip.state.get_directly_installed()));
        end

        function testLoadPackage_PromotesTransitiveDepWhenLoadedDirectly(testCase)
            % Issue #224: if a package was already loaded as a transitive
            % dependency, a subsequent direct mip.load on it must promote
            % it to directly_installed so a later uninstall of the parent
            % does not prune it.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            mip.load('mip-org/core/mainpkg');
            testCase.verifyFalse( ...
                ismember('gh/mip-org/core/depA', mip.state.get_directly_installed()));

            mip.load('mip-org/core/depA');

            testCase.verifyTrue( ...
                ismember('gh/mip-org/core/depA', mip.state.get_directly_installed()));
        end

        function testLoadPackage_LoadedDepSurvivesParentUninstall(testCase)
            % Full issue #224 scenario: install mainpkg (which pulls in
            % depA as a transitive dep), then `mip load depA`, then
            % uninstall mainpkg. depA must NOT be pruned.
            depDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'depA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'depA'});
            % Simulate `mip install mainpkg` having marked mainpkg (and
            % only mainpkg) as directly_installed.
            mip.state.add_directly_installed('mip-org/core/mainpkg');

            mip.load('mip-org/core/depA');
            mip.uninstall('mip-org/core/mainpkg');

            testCase.verifyTrue(exist(depDir, 'dir') > 0, ...
                'depA must not be pruned: it was directly loaded');
        end

    end
end

function removePathsField(mipJsonPath)
%REMOVEPATHSFIELD   Rewrite mip.json with the "paths" field stripped.
    text = fileread(mipJsonPath);
    data = jsondecode(text);
    if isfield(data, 'paths')
        data = rmfield(data, 'paths');
    end
    fid = fopen(mipJsonPath, 'w');
    fwrite(fid, jsonencode(data));
    fclose(fid);
end
