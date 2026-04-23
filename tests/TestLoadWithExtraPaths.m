classdef TestLoadWithExtraPaths < matlab.unittest.TestCase
%TESTLOADWITHEXTRAPATHS   Tests for `mip load --with <group>` and the
% extra_paths field in mip.json.
%
% These tests focus on load-time behavior. The list of paths under each
% group in mip.json is whatever was written at install time (possibly
% the result of a recursive walk via `recursive: true` in the yaml);
% load just iterates the list it finds. Install-time resolution of
% extra_paths is covered by the prepare_package / compute_addpaths
% tests.

    properties
        OrigMipRoot
        TestRoot
        SavedPath
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_with_test'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.SavedPath = path;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            path(testCase.SavedPath);
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
            clearMipState();
        end
    end

    methods (Test)

        %% --- Flag parsing / validation ---

        function testWith_MissingValue_Errors(testCase)
            % --with with no following token must surface a parse error
            % rather than silently consuming the next positional arg.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            testCase.verifyError(@() mip.load('foo', '--with'), ...
                'mip:load:missingWithValue');
        end

        %% --- Group declared: addpath applied ---

        function testWith_AddsDeclaredGroupPaths(testCase)
            % Happy path: package declares extra_paths.examples and
            % --with examples puts that directory on the MATLAB path.
            extras = struct('examples', {{'examples'}});
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'examples'}, 'extraPaths', extras);
            mip.load('foo', '--with', 'examples');
            expected = fullfile(pkgDir, 'foo', 'examples');
            testCase.verifyTrue(onPath(expected), ...
                sprintf('expected %s on path after --with examples', expected));
        end

        function testWith_MultipleGroupsAccumulate(testCase)
            % Repeating --with should accumulate: both groups' entries
            % land on the path in a single load call.
            extras = struct();
            extras.examples = {'examples'};
            extras.tests = {'tests'};
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'examples', 'tests'}, 'extraPaths', extras);
            mip.load('foo', '--with', 'examples', '--with', 'tests');
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'examples')));
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'tests')));
        end

        function testWith_MultiEntryGroupInMipJson(testCase)
            % When the resolved list under a group in mip.json has
            % multiple entries, load iterates and addpaths each one.
            % (The list's shape in mip.json is whatever prepare_package
            % wrote -- direct list, or a recursive: true walk's output;
            % load treats them identically.)
            extras = struct('examples', {{'examples', 'examples/advanced'}});
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'examples/advanced'}, 'extraPaths', extras);
            mip.load('foo', '--with', 'examples');
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'examples')));
            testCase.verifyTrue(onPath(fullfile(pkgDir, 'foo', 'examples', 'advanced')));
        end

        %% --- Group NOT declared: silent per-package, warn globally ---

        function testWith_UnknownGroup_WarnsWhenNoPackageDeclaresIt(testCase)
            % If the requested group is not declared by any loaded
            % package, emit mip:load:unknownGroup (catches both typos
            % and genuinely-missing extras in one signal).
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo');
            testCase.verifyWarning( ...
                @() mip.load('foo', '--with', 'examples'), ...
                'mip:load:unknownGroup');
        end

        function testWith_PartialMatch_NoWarningWhenOnePackageHasIt(testCase)
            % Bundle semantics: as long as at least one package in the
            % load set declared the group, no warning fires. Packages
            % that don't declare it are silently no-op'd.
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'plain');
            extras = struct('examples', {{'examples'}});
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'fancy', ...
                'subdirs', {'examples'}, 'extraPaths', extras);

            warnState = warning('off', 'mip:load:unknownGroup');
            warning('');  % clear lastwarn
            restoreWarn = onCleanup(@() warning(warnState));
            mip.load('plain', 'fancy', '--with', 'examples');
            [~, lastId] = lastwarn;
            clear restoreWarn;

            testCase.verifyNotEqual(lastId, 'mip:load:unknownGroup', ...
                'no warning expected when at least one package declares the group');
        end

        %% --- Bundle behavior across multiple packages ---

        function testWith_AppliedPerPackage(testCase)
            % --with is package-agnostic: each loaded package's own
            % extra_paths.<group> is applied to that package's source
            % dir. Positional packages do NOT share a single resolution.
            extrasA = struct('examples', {{'examples'}});
            extrasB = struct('examples', {{'examples'}});
            pkgA = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkg_a', ...
                'subdirs', {'examples'}, 'extraPaths', extrasA);
            pkgB = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkg_b', ...
                'subdirs', {'examples'}, 'extraPaths', extrasB);

            mip.load('pkg_a', 'pkg_b', '--with', 'examples');

            testCase.verifyTrue(onPath(fullfile(pkgA, 'pkg_a', 'examples')));
            testCase.verifyTrue(onPath(fullfile(pkgB, 'pkg_b', 'examples')));
        end

        %% --- Transitive dependencies: --with does NOT propagate ---

        function testWith_NotPropagatedToDependencies(testCase)
            % A dependency can declare an `examples` group, but --with
            % on a parent package must not addpath the dep's examples.
            % This matches --addpath's direct-load-only policy. Since
            % `main` itself does not declare examples, we also expect
            % the unknownGroup warning.
            extrasDep = struct('examples', {{'examples'}});
            depDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'dep1', ...
                'subdirs', {'examples'}, 'extraPaths', extrasDep);
            mainDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'main', ...
                'dependencies', {'dep1'});

            testCase.verifyWarning( ...
                @() mip.load('main', '--with', 'examples'), ...
                'mip:load:unknownGroup');

            testCase.verifyFalse( ...
                onPath(fullfile(depDir, 'dep1', 'examples')), ...
                '--with must not propagate to dependencies');
            testCase.verifyTrue(onPath(fullfile(mainDir, 'main')), ...
                'main package should still be loaded');
        end

        %% --- Already-loaded package: --with still applies ---

        function testWith_AppliesToAlreadyLoaded(testCase)
            % Mirrors --addpath's "already-loaded" behavior: a user can
            % add extras to an already-loaded package without a reload.
            extras = struct('examples', {{'examples'}});
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'examples'}, 'extraPaths', extras);
            mip.load('foo');
            testCase.verifyFalse( ...
                onPath(fullfile(pkgDir, 'foo', 'examples')), ...
                'examples dir should not be on path after plain load');
            mip.load('foo', '--with', 'examples');
            testCase.verifyTrue( ...
                onPath(fullfile(pkgDir, 'foo', 'examples')), ...
                '--with on already-loaded package should addpath the group');
        end

        %% --- Unload cleans up extras via defensive sweep ---

        function testUnload_SweepsWithEntries(testCase)
            % Extras live under srcDir, so unload's defensive sweep
            % catches them (no explicit tracking list needed).
            extras = struct('examples', {{'examples'}});
            pkgDir = createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'foo', ...
                'subdirs', {'examples'}, 'extraPaths', extras);
            mip.load('foo', '--with', 'examples');
            target = fullfile(pkgDir, 'foo', 'examples');
            testCase.verifyTrue(onPath(target));

            mip.unload('foo');
            testCase.verifyFalse(onPath(target), ...
                'unload sweep should remove --with extra paths');
        end

    end
end


function tf = onPath(p)
    tf = ismember(p, strsplit(path, pathsep));
end
