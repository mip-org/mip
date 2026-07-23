classdef TestEnvActivate < matlab.unittest.TestCase
%TESTENVACTIVATE   Tests for "mip activate" / "mip deactivate" (MEP 8).

    properties
        OrigMipRoot
        OrigDir
        TestRoot
        WorkDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigDir = pwd;
            testCase.TestRoot = [tempname '_mip_env_activate_root'];
            testCase.WorkDir = [tempname '_mip_env_activate_work'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigDir);
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.WorkDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            if exist(testCase.WorkDir, 'dir')
                rmdir(testCase.WorkDir, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        function testActivateNamedSetsPointer(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');

            expected = mip.paths.get_absolute_path( ...
                fullfile(testCase.TestRoot, 'envs', 'scratch'));
            testCase.verifyEqual(getenv('MIP_ROOT'), expected, ...
                'Activation must point MIP_ROOT at the env');
            testCase.verifyEqual(mip.paths.root(), expected, ...
                'mip.paths.root() must resolve to the active env');

            s = mip.state.get_env_state();
            testCase.verifyEqual(s.name, 'scratch');
            testCase.verifyEqual(s.root, expected);
        end

        function testActivateNoArgUsesCwdDotMip(testCase)
            cd(testCase.WorkDir);
            evalc('mip.env(''create'')');
            evalc('mip.env(''activate'')');

            expected = mip.paths.get_absolute_path( ...
                fullfile(testCase.WorkDir, '.mip'));
            testCase.verifyEqual(getenv('MIP_ROOT'), expected);
            s = mip.state.get_env_state();
            testCase.verifyEmpty(s.name, 'A path env has no name');
        end

        function testActivateDotMipIsPathArg(testCase)
            % '.mip' is a path argument (explicitly written as a path,
            % though it has no separator), equivalent to no-arg activate.
            cd(testCase.WorkDir);
            evalc('mip.env(''create'')');
            evalc('mip.env(''activate'', ''.mip'')');

            expected = mip.paths.get_absolute_path( ...
                fullfile(testCase.WorkDir, '.mip'));
            testCase.verifyEqual(getenv('MIP_ROOT'), expected);
            testCase.verifyEmpty(mip.state.get_env_state().name, ...
                'A path env has no name');
        end

        function testActivateRefusesNonEnv(testCase)
            testCase.verifyError(@() mip.env('activate', 'ghost'), ...
                'mip:env:notAnEnvironment');
            emptyDir = fullfile(testCase.WorkDir, 'notanenv');
            mkdir(emptyDir);
            testCase.verifyError(@() mip.env('activate', emptyDir), ...
                'mip:env:notAnEnvironment');
            % The pointer must be untouched by a failed activation.
            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot);
        end

        function testActivateSwapsAndDeactivateRestores(testCase)
            % Load a package (sticky) in the base root, activate an
            % env (full swap: everything unloads, sticky included), then
            % deactivate (saved set restored with its flags).
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkga');
            srcDir = fullfile(pkgDir, 'pkga');
            evalc('mip.load(''pkga'', ''--sticky'')');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));

            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');

            testCase.verifyFalse(ismember(srcDir, strsplit(path, pathsep)), ...
                'Activation must unload everything, sticky included');
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/pkga'));
            testCase.verifyEqual(mip.state.key_value_get('MIP_LOADED_PACKAGES'), ...
                {'gh/mip-org/core/mip'}, ...
                'The env session starts at the usual baseline (mip only)');

            evalc('mip.env(''deactivate'')');

            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot, ...
                'Deactivation must restore the prior MIP_ROOT');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/pkga'), ...
                'The saved package set must be restored');
            testCase.verifyTrue(mip.state.is_directly_loaded('gh/mip-org/core/pkga'));
            testCase.verifyTrue(mip.state.is_sticky('gh/mip-org/core/pkga'), ...
                'Sticky flags must be restored');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)), ...
                'The package must be back on the path');
        end

        function testDeactivateRestoresLoadOrder(testCase)
            % Seed the mip identity as the dispatcher does, so the saved
            % list matches the post-restore baseline shape.
            mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/mip');
            mip.state.key_value_append('MIP_STICKY_PACKAGES', 'gh/mip-org/core/mip');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkga');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgb');
            evalc('mip.load(''pkga'')');
            evalc('mip.load(''pkgb'')');
            orderBefore = mip.state.key_value_get('MIP_LOADED_PACKAGES');

            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            evalc('mip.env(''deactivate'')');

            testCase.verifyEqual(mip.state.key_value_get('MIP_LOADED_PACKAGES'), ...
                orderBefore, 'Restoration must preserve the original load order');
        end

        function testActivateAnotherEnvAutoDeactivates(testCase)
            evalc('mip.env(''create'', ''one'')');
            evalc('mip.env(''create'', ''two'')');
            evalc('mip.env(''activate'', ''one'')');
            evalc('mip.env(''activate'', ''two'')');

            s = mip.state.get_env_state();
            testCase.verifyEqual(s.name, 'two');
            testCase.verifyEqual(s.saved_mip_root, testCase.TestRoot, ...
                'The saved state must be the base session''s, not env one''s');

            evalc('mip.env(''deactivate'')');
            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot);
            testCase.verifyEmpty(mip.state.get_env_state());
        end

        function testReactivateSameEnvIsNoOp(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            output = evalc('mip.env(''activate'', ''scratch'')');
            testCase.verifyTrue(contains(output, 'already active'));
        end

        function testActivateWithLoadLoadsDirectInstalls(testCase)
            evalc('mip.env(''create'', ''scratch'')');
            envRoot = fullfile(testCase.TestRoot, 'envs', 'scratch');

            % Seed the env: a directly installed package with a dependency,
            % plus a directly-installed entry whose package is missing (its
            % load must fail without breaking activation).
            createTestPackage(envRoot, 'mip-org', 'core', 'dep1');
            pkgDir = createTestPackage(envRoot, 'mip-org', 'core', 'mainpkg', ...
                'dependencies', {'dep1'});
            evalc('mip.env(''activate'', ''scratch'')');
            mip.state.add_directly_installed('gh/mip-org/core/mainpkg');
            mip.state.add_directly_installed('gh/mip-org/core/ghost');
            evalc('mip.env(''deactivate'')');

            output = evalc('mip.env(''activate'', ''scratch'', ''--load'')');

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/mainpkg'));
            testCase.verifyTrue(mip.state.is_directly_loaded('gh/mip-org/core/mainpkg'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/dep1'), ...
                'Dependencies load transitively');
            testCase.verifyFalse(mip.state.is_directly_loaded('gh/mip-org/core/dep1'));
            testCase.verifyTrue(ismember(fullfile(pkgDir, 'mainpkg'), ...
                strsplit(path, pathsep)));
            testCase.verifyTrue(contains(output, 'Loaded 1 package(s), 1 failed'), ...
                'The load pass is best-effort and ends with a summary');
            testCase.verifyNotEmpty(mip.state.get_env_state(), ...
                'The env stays active regardless of load failures');

            evalc('mip.env(''deactivate'')');
        end

        function testDeactivateWhenNoneActive(testCase)
            output = evalc('mip.env(''deactivate'')');
            testCase.verifyTrue(contains(output, 'No environment is active'));
            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot);
        end

        function testDeactivateSurvivesDeletedEnvDir(testCase)
            evalc('mip.env(''create'', ''doomed'')');
            envRoot = mip.paths.get_absolute_path( ...
                fullfile(testCase.TestRoot, 'envs', 'doomed'));
            evalc('mip.env(''activate'', ''doomed'')');
            pkgDir = createTestPackage(envRoot, 'mip-org', 'core', 'envpkg');
            evalc('mip.load(''envpkg'')');
            srcDir = fullfile(pkgDir, 'envpkg');
            testCase.verifyTrue(ismember(srcDir, strsplit(path, pathsep)));

            rmdir(envRoot, 's');
            evalc('mip.env(''deactivate'')');

            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot, ...
                'Deactivation must work after the env dir is gone');
            testCase.verifyFalse(ismember(srcDir, strsplit(path, pathsep)), ...
                'Path entries under the deleted env must be swept');
            testCase.verifyEmpty(mip.state.get_env_state());
        end

        function testEnvStatusReportsActiveEnv(testCase)
            output = evalc('mip.env()');
            testCase.verifyTrue(contains(output, 'no active environment'));

            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));
            output = evalc('mip.env()');
            testCase.verifyTrue(contains(output, 'active environment: scratch'));
        end

        function testEnvironmentBannerOnMutatingCommands(testCase)
            output = evalc('mip.list()');
            testCase.verifyFalse(contains(output, 'environment:'), ...
                'No banner when no env is active (the global root is a first-class target)');

            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));

            output = evalc('mip.list()');
            testCase.verifyTrue(startsWith(output, 'environment: scratch'), ...
                'mip list must lead with the environment line while active');

            output = evalc('mip.info()');
            testCase.verifyTrue(contains(output, 'Environment:  scratch'), ...
                'mip info must report the active environment');
        end

        function testSessionCommandsTargetActiveEnv(testCase)
            % Install state is per-root: a package installed in the
            % base root is invisible while an env is active.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'basepkg');
            testCase.verifyTrue(mip.state.is_installed('gh/mip-org/core/basepkg'));

            evalc('mip.env(''create'', ''scratch'')');
            evalc('mip.env(''activate'', ''scratch'')');
            testCase.addTeardown(@() evalc('mip.env(''deactivate'')'));

            testCase.verifyFalse(mip.state.is_installed('gh/mip-org/core/basepkg'), ...
                'Session commands must act on the active env only');
            testCase.verifyError(@() mip.load('basepkg'), 'mip:packageNotFound');
        end

    end
end
