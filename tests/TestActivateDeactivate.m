classdef TestActivateDeactivate < matlab.unittest.TestCase
%TESTACTIVATEDEACTIVATE   Tests for mip.activate / mip.deactivate:
%   the full session swap, --load, the baseline store anchoring, the
%   "environment:" header line, and the mip-identity keying inside an
%   active environment.

    properties
        OrigMipRoot
        OrigMipConfirm
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.OrigMipConfirm = getenv('MIP_CONFIRM');
            testCase.TestRoot = [tempname '_mip_activate_test'];
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
            setenv('MIP_CONFIRM', testCase.OrigMipConfirm);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        % ---- validation ----

        function testActivateMissingEnvErrors(testCase)
            testCase.verifyError(@() mip.activate('nosuch'), ...
                'mip:env:notFound');
        end

        function testActivateNonEnvDirErrors(testCase)
            plainDir = fullfile(testCase.TestRoot, 'plain');
            mkdir(plainDir);
            testCase.verifyError(@() mip.activate(plainDir), ...
                'mip:env:notAnEnvironment');
        end

        function testActivateEnvMissingPackagesErrors(testCase)
            broken = fullfile(testCase.TestRoot, 'envs', 'broken');
            mkdir(broken);
            fid = fopen(fullfile(broken, 'mip-env.json'), 'w');
            fwrite(fid, '{"format_version":1}');
            fclose(fid);

            testCase.verifyError(@() mip.activate('broken'), ...
                'mip:env:invalid');
        end

        % ---- pointer swap ----

        function testActivatePointsSessionAtEnv(testCase)
            mip.env.create('scratch');
            envPath = fullfile(testCase.TestRoot, 'envs', 'scratch');

            mip.activate('scratch');

            testCase.verifyEqual(getenv('MIP_ROOT'), envPath);
            testCase.verifyEqual(mip.paths.root(), envPath);
            env = mip.state.get_active_env();
            testCase.verifyEqual(env.name, 'scratch');
            testCase.verifyEqual(env.path, envPath);
            testCase.verifyEqual(env.saved.mip_root, testCase.TestRoot);
        end

        function testActivateUnloadsEverythingIncludingSticky(testCase)
            pkgA = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgB');
            mip.load('mip-org/core/pkgA');
            mip.load('mip-org/core/pkgB', '--sticky');
            mip.env.create('scratch');

            mip.activate('scratch');

            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/pkgA'));
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/pkgB'), ...
                'sticky packages should also be unloaded by the swap');
            srcA = fullfile(pkgA, 'pkgA');
            testCase.verifyFalse(ismember(srcA, strsplit(path, pathsep)), ...
                'path entries from the old root should be removed');
            testCase.verifyEqual(mip.state.key_value_get('MIP_LOADED_PACKAGES'), ...
                {'gh/mip-org/core/mip'}, ...
                'load state should be reset to the baseline (mip only)');
        end

        function testDeactivateRestoresSavedSession(testCase)
            pkgA = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgB');
            mip.load('mip-org/core/pkgA');
            mip.load('mip-org/core/pkgB', '--sticky');
            mip.env.create('scratch');
            mip.activate('scratch');
            envPath = fullfile(testCase.TestRoot, 'envs', 'scratch');
            createTestPackage(envPath, 'mip-org', 'core', 'envpkg');
            mip.load('mip-org/core/envpkg');

            mip.deactivate();

            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot, ...
                'MIP_ROOT should be restored to the baseline root');
            testCase.verifyEmpty(mip.state.get_active_env());
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/envpkg'), ...
                'the env''s packages should be unloaded');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/pkgA'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/pkgB'));
            testCase.verifyTrue(mip.state.is_sticky('gh/mip-org/core/pkgB'), ...
                'sticky flags should be restored');
            srcA = fullfile(pkgA, 'pkgA');
            testCase.verifyTrue(ismember(srcA, strsplit(path, pathsep)), ...
                'restored packages should be back on the path');
        end

        function testDeactivateWithNoActiveEnv(testCase)
            output = evalc('mip.deactivate()');
            testCase.verifyTrue(contains(output, 'No environment is active'));
        end

        function testReactivateSameEnvIsNoop(testCase)
            mip.env.create('scratch');
            mip.activate('scratch');

            output = evalc('mip.activate(''scratch'')');

            testCase.verifyTrue(contains(output, 'already active'));
            env = mip.state.get_active_env();
            testCase.verifyEqual(env.name, 'scratch');
        end

        function testActivateOtherEnvAutoDeactivates(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            mip.load('mip-org/core/pkgA');
            mip.env.create('one');
            mip.env.create('two');

            mip.activate('one');
            mip.activate('two');

            env = mip.state.get_active_env();
            testCase.verifyEqual(env.name, 'two');
            testCase.verifyEqual(env.saved.mip_root, testCase.TestRoot, ...
                'saved state must be the baseline session''s, not env one''s');

            mip.deactivate();
            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot);
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/pkgA'), ...
                'baseline session should be restored after the env chain');
        end

        % ---- --load ----

        function testActivateLoadLoadsDirectlyInstalled(testCase)
            envPath = seedEnvWithPackages(testCase, 'scratch');

            output = evalc('mip.activate(''scratch'', ''--load'')');

            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/direct1'));
            testCase.verifyTrue(mip.state.is_directly_loaded('gh/mip-org/core/direct1'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/dep1'), ...
                'dependencies should load transitively');
            testCase.verifyFalse(mip.state.is_directly_loaded('gh/mip-org/core/dep1'));
            testCase.verifyTrue(contains(output, 'Loaded 1 package(s)'));
            testCase.verifyEqual(mip.state.get_active_env().path, envPath);
        end

        function testActivateLoadIsBestEffort(testCase)
            envPath = seedEnvWithPackages(testCase, 'scratch');
            directFile = fullfile(envPath, 'packages', 'directly_installed.txt');
            mip.state.write_line_list(directFile, ...
                {'gh/mip-org/core/direct1', 'gh/mip-org/core/missingpkg'});

            output = evalc('mip.activate(''scratch'', ''--load'')');

            testCase.verifyTrue(contains(output, 'Failed to load'));
            testCase.verifyTrue(contains(output, '1 failed'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/direct1'));
            env = mip.state.get_active_env();
            testCase.verifyEqual(env.name, 'scratch', ...
                'the environment stays active despite load failures');
        end

        function testReactivateWithLoadStillLoads(testCase)
            seedEnvWithPackages(testCase, 'scratch');
            mip.activate('scratch');
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/direct1'), ...
                'default activation is pointer-only');

            output = evalc('mip.activate(''scratch'', ''--load'')');

            testCase.verifyTrue(contains(output, 'already active'));
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/core/direct1'), ...
                '--load should still perform its load pass on the active env');
        end

        % ---- resilience ----

        function testDeactivateAfterEnvDirDeleted(testCase)
            envPath = seedEnvWithPackages(testCase, 'scratch');
            mip.activate('scratch', '--load');
            rmdir(envPath, 's');

            w = warning('off', 'all');
            restoreWarn = onCleanup(@() warning(w)); %#ok<NASGU>
            mip.deactivate();

            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot);
            testCase.verifyEmpty(mip.state.get_active_env());
            entries = strsplit(path, pathsep);
            under = startsWith(entries, [envPath, filesep]);
            testCase.verifyFalse(any(under), ...
                'path entries under the deleted env should be swept');
        end

        % ---- visibility ----

        function testHeaderLinePrintedWhenEnvActive(testCase)
            mip.env.create('scratch');
            mip.activate('scratch');

            output = evalc('mip.list()');

            testCase.verifyTrue(contains(output, 'environment: scratch'));
        end

        function testNoHeaderLineWithoutEnv(testCase)
            output = evalc('mip.list()');
            testCase.verifyFalse(contains(output, 'environment:'));
        end

        function testInfoReportsActiveEnv(testCase)
            mip.env.create('scratch');
            mip.activate('scratch');

            output = evalc('mip.info()');

            testCase.verifyTrue(contains(output, 'Environment:'));
            testCase.verifyTrue(contains(output, 'scratch'));
        end

        % ---- baseline store anchoring ----

        function testNamedEnvOpsResolveAgainstBaselineStore(testCase)
            mip.env.create('one');
            mip.activate('one');

            mip.env.create('two');

            testCase.verifyTrue(mip.env.is_env( ...
                fullfile(testCase.TestRoot, 'envs', 'two')), ...
                'env create must target the baseline store, not the active env');
            output = evalc('mip.env.list()');
            testCase.verifyTrue(contains(output, '* one'));
            testCase.verifyTrue(contains(output, 'two'));
        end

        % ---- mip identity inside an env ----

        function testRunningMipCopySurvivesActivateDeactivate(testCase)
            % A session may run mip from a copy other than
            % gh/mip-org/core/mip (e.g. a preview build loaded with
            % "mip load mip-org/labs/mip"). The full swap must not unload
            % the running copy - otherwise the very commands being used
            % would vanish from the path mid-activation.
            createTestPackage(testCase.TestRoot, 'mip-org', 'labs', 'mip');
            mip.load('mip-org/labs/mip');
            setappdata(0, 'MIP_SELF_FQN', 'gh/mip-org/labs/mip');
            mip.env.create('scratch');

            mip.activate('scratch');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'the running mip copy must survive the activation swap');

            mip.deactivate();
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'the running mip copy must survive deactivation too');
        end

        function testRunningMipCopySurvivesUnloadAllButNotExplicitUnload(testCase)
            createTestPackage(testCase.TestRoot, 'mip-org', 'labs', 'mip');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkgA');
            mip.load('mip-org/labs/mip');
            mip.load('mip-org/core/pkgA');
            setappdata(0, 'MIP_SELF_FQN', 'gh/mip-org/labs/mip');

            mip.unload('--all');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'));
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/core/pkgA'));

            mip.unload('--all', '--force');
            testCase.verifyTrue(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'the running copy survives --all --force');

            % The documented way back to the released mip stays available.
            mip.unload('mip-org/labs/mip');
            testCase.verifyFalse(mip.state.is_loaded('gh/mip-org/labs/mip'), ...
                'an explicit unload of the running copy is still allowed');
        end

        function testUninstallMipInsideEnvIsOrdinary(testCase)
            mip.env.create('scratch');
            mip.activate('scratch');
            envPath = fullfile(testCase.TestRoot, 'envs', 'scratch');
            mipCopyDir = createTestPackage(envPath, 'mip-org', 'core', 'mip');
            mip.state.add_directly_installed('gh/mip-org/core/mip');
            setenv('MIP_CONFIRM', 'yes');

            mip.uninstall('mip-org/core/mip');

            testCase.verifyFalse(exist(mipCopyDir, 'dir') > 0, ...
                'the env''s inert mip copy should be uninstalled');
            testCase.verifyTrue(exist(envPath, 'dir') > 0, ...
                'self-uninstall must never tear down an environment root');
            testCase.verifyEqual(getenv('MIP_ROOT'), envPath, ...
                'the environment stays active');
        end

    end

    methods (Access = private)

        function envPath = seedEnvWithPackages(testCase, envName)
            % Create an environment holding direct1 (which depends on
            % dep1) and mark direct1 as directly installed, without
            % activating it.
            mip.env.create(envName);
            envPath = fullfile(testCase.TestRoot, 'envs', envName);
            createTestPackage(envPath, 'mip-org', 'core', 'direct1', ...
                'dependencies', {'dep1'});
            createTestPackage(envPath, 'mip-org', 'core', 'dep1');
            directFile = fullfile(envPath, 'packages', 'directly_installed.txt');
            mip.state.write_line_list(directFile, {'gh/mip-org/core/direct1'});
        end

    end
end
