classdef TestRepoPackages < matlab.unittest.TestCase
%TESTREPOPACKAGES   Packages published from their own GitHub repository (MEP 10).
%
% A repository package has the 3-part FQN gh/<owner>/<repo> and is
% installed at packages/gh/<owner>/<repo>/, next to the channels of the
% same owner. These tests use synthetic repository indexes written to the
% fetch_index cache (writeRepoIndex) and .mhl files bundled locally, so
% they need no network access.

    properties
        OrigMipRoot
        TestRoot
        SourceDir
        BundleDir
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_repo_test'];
            testCase.SourceDir = [tempname '_mip_repo_src'];
            testCase.BundleDir = [tempname '_mip_repo_bundle'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.SourceDir);
            mkdir(testCase.BundleDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            clearMipState();
            % Installs always consult mip-org/core; keep it offline.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cleanupTestPaths(testCase.TestRoot);
            cleanupTestPaths(testCase.SourceDir);
            cleanupTestPaths(testCase.BundleDir);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            for d = {testCase.TestRoot, testCase.SourceDir, testCase.BundleDir}
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        %% Install

        function testInstallTwoPartForm(testCase)
            mhl = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl)});

            evalc('mip.install(''myorg/repopkg'')');

            pkgDir = fullfile(testCase.TestRoot, 'packages', 'gh', 'myorg', 'repopkg');
            testCase.verifyTrue(isfile(fullfile(pkgDir, 'mip.json')));
            testCase.verifyTrue(ismember('gh/myorg/repopkg', mip.state.get_directly_installed()));
            testCase.verifyEqual(mip.state.list_installed_packages(), {'gh/myorg/repopkg'});
        end

        function testInstallUrlFormsAndVersion(testCase)
            mhl1 = bundle(testCase, 'repopkg', '1.0.0');
            mhl2 = bundle(testCase, 'repopkg', '2.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl1), entry('repopkg', '2.0.0', mhl2)});

            evalc('mip.install(''https://github.com/myorg/repopkg.git@1.0.0'')');
            testCase.verifyEqual(installedVersion(testCase, 'myorg', 'repopkg'), '1.0.0');

            % The scheme-less form with a different @version replaces it.
            evalc('mip.install(''github.com/myorg/repopkg@2.0.0'')');
            testCase.verifyEqual(installedVersion(testCase, 'myorg', 'repopkg'), '2.0.0');
        end

        function testInstallCanonicalizesOwnerFromIndex(testCase)
            % GitHub names are case-insensitive; the FQN takes the owner
            % spelling of the index's github_repo field.
            mhl = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl)}, 'MyOrg/RepoPkg');

            evalc('mip.install(''myorg/repopkg'')');

            testCase.verifyEqual(mip.state.list_installed_packages(), {'gh/MyOrg/repopkg'});
        end

        function testInstallRejectsIndexWithTwoNames(testCase)
            mhl = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl), entry('other', '1.0.0', mhl)});
            testCase.verifyError(@() evalc('mip.install(''myorg/repopkg'')'), ...
                'mip:repo:invalidIndex');
        end

        function testInstallRejectsNameMismatch(testCase)
            mhl = bundle(testCase, 'other', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('other', '1.0.0', mhl)});
            testCase.verifyError(@() evalc('mip.install(''myorg/repopkg'')'), ...
                'mip:repo:invalidIndex');
        end

        function testInvalidIndexIsNotMaskedByFallback(testCase)
            % Only a missing index (404) triggers the personal-channel
            % fallback; an invalid index is raised.
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', {});
            writeChannelIndex(testCase.TestRoot, 'myorg/myorg', {'repopkg'});
            testCase.verifyError(@() evalc('mip.install(''myorg/repopkg'')'), ...
                'mip:repo:invalidIndex');
        end

        function testInstallWithBareDependencyFromCore(testCase)
            % A bare-name dependency of a repository package resolves to
            % mip-org/core, not to another repository of the same owner.
            depMhl = bundle(testCase, 'depx', '1.0.0');
            mhl = bundle(testCase, 'repopkg', '1.0.0', {'depx'});
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', ...
                {entry('depx', '1.0.0', depMhl)});
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl, {'depx'})});

            evalc('mip.install(''myorg/repopkg'')');

            testCase.verifyEqual(sort(mip.state.list_installed_packages()), ...
                sort({'gh/mip-org/core/depx', 'gh/myorg/repopkg'}));
        end

        function testInstallWithRepoDependency(testCase)
            % One repository package depending on another, written as
            % github.com/<owner>/<repo> with a different owner spelling.
            depMhl = bundle(testCase, 'depy', '1.0.0');
            mhl = bundle(testCase, 'repopkg', '1.0.0', {'github.com/Other/depy'});
            writeRepoIndex(testCase.TestRoot, 'Other/depy', ...
                {entry('depy', '1.0.0', depMhl)}, 'other/depy');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl, {'github.com/Other/depy'})});

            evalc('mip.install(''myorg/repopkg'')');

            testCase.verifyEqual(sort(mip.state.list_installed_packages()), ...
                sort({'gh/myorg/repopkg', 'gh/other/depy'}));
            % The dependency is transitive, so it is pruned with its parent.
            evalc('mip.uninstall(''myorg/repopkg'')');
            testCase.verifyEmpty(mip.state.list_installed_packages());
        end

        function testTwoPartDependencyRejected(testCase)
            map = containers.Map();
            map('gh/myorg/repopkg') = struct('dependencies', {{'other/depy'}});
            testCase.verifyError(@() mip.dependency.build_graph('gh/myorg/repopkg', map), ...
                'mip:invalidDependency');
        end

        function testBareDependencyIgnoresSameOwnerRepo(testCase)
            map = containers.Map();
            map('gh/myorg/repopkg') = struct('dependencies', {{'depx'}});
            map('gh/myorg/depx') = struct('dependencies', {{}});
            map('gh/mip-org/core/depx') = struct('dependencies', {{}});
            order = mip.dependency.build_graph('gh/myorg/repopkg', map);
            testCase.verifyEqual(order, {'gh/mip-org/core/depx', 'gh/myorg/repopkg'});
        end

        function testResolveDependencyOfRepoParentGoesToCore(testCase)
            createTestPackage(testCase.TestRoot, 'myorg', '', 'depx');
            testCase.verifyEqual( ...
                mip.resolve.resolve_dependency('depx', 'gh/myorg/repopkg'), ...
                'gh/mip-org/core/depx');
        end

        %% Installed-package commands and on-disk layout

        function testLoadUnloadUninstall(testCase)
            mhl = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl)});
            evalc('mip.install(''myorg/repopkg'')');

            evalc('mip.load(''myorg/repopkg'')');
            testCase.verifyTrue(mip.state.is_loaded('gh/myorg/repopkg'));
            evalc('mip.unload(''repopkg'')');
            testCase.verifyFalse(mip.state.is_loaded('gh/myorg/repopkg'));
            evalc('mip.load(''gh/myorg/repopkg'')');
            testCase.verifyTrue(mip.state.is_loaded('myorg/repopkg'));
            evalc('mip.unload(''myorg/repopkg'')');

            evalc('mip.uninstall(''https://github.com/myorg/repopkg'')');
            testCase.verifyEmpty(mip.state.list_installed_packages());
            testCase.verifyFalse(isfolder(fullfile(testCase.TestRoot, 'packages', 'gh')), ...
                'empty parent directories should be removed');
        end

        function testTwoPartResolvesToInstalledPersonalChannel(testCase)
            createTestPackage(testCase.TestRoot, 'magland', 'magland', 'chunkie');
            testCase.verifyEqual(mip.resolve.installed_fqn('magland/chunkie'), ...
                'gh/magland/magland/chunkie');
            testCase.verifyEqual(mip.parse.canonical_fqn('magland/chunkie'), ...
                'gh/magland/magland/chunkie');
            r = mip.resolve.resolve_to_installed('magland/chunkie');
            testCase.verifyEqual(r.fqn, 'gh/magland/magland/chunkie');

            % With the repository package also installed, it wins.
            createTestPackage(testCase.TestRoot, 'magland', '', 'chunkie');
            testCase.verifyEqual(mip.resolve.installed_fqn('magland/chunkie'), ...
                'gh/magland/chunkie');
            testCase.verifyEqual(mip.parse.canonical_fqn('magland/chunkie'), ...
                'gh/magland/chunkie');
        end

        function testListDistinguishesRepoFromChannel(testCase)
            createTestPackage(testCase.TestRoot, 'myorg', 'tools', 'pkga');
            createTestPackage(testCase.TestRoot, 'myorg', '', 'repopkg');
            testCase.verifyEqual(mip.state.list_installed_packages(), ...
                {'gh/myorg/repopkg', 'gh/myorg/tools/pkga'});
            testCase.verifyEqual(mip.resolve.resolve_bare_name('repopkg'), 'gh/myorg/repopkg');
        end

        function testChannelFqnDoesNotMatchInsideRepoPackage(testCase)
            % createTestPackage places a source subdirectory named after
            % the package inside the package directory; a channel FQN
            % must not mistake it for a channel package.
            createTestPackage(testCase.TestRoot, 'myorg', '', 'foo');
            testCase.verifyEqual(mip.resolve.installed_dir('gh/myorg/foo/foo'), '');
            testCase.verifyEqual(mip.resolve.installed_dir('gh/myorg/foo'), 'foo');
            % And a repository FQN does not match a channel directory.
            createTestPackage(testCase.TestRoot, 'myorg', 'tools', 'pkga');
            testCase.verifyEqual(mip.resolve.installed_dir('gh/myorg/tools'), '');
        end

        function testRepoInstallConflictsWithChannel(testCase)
            createTestPackage(testCase.TestRoot, 'myorg', 'repopkg', 'pkga');
            mhl = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl)});
            testCase.verifyError(@() evalc('mip.install(''myorg/repopkg'')'), ...
                'mip:repo:conflictsWithChannel');
        end

        function testChannelInstallConflictsWithRepo(testCase)
            createTestPackage(testCase.TestRoot, 'myorg', '', 'tools');
            mhl = bundle(testCase, 'pkga', '1.0.0');
            writeChannelIndex(testCase.TestRoot, 'myorg/tools', ...
                {entry('pkga', '1.0.0', mhl)});
            testCase.verifyError(@() evalc('mip.install(''myorg/tools/pkga'')'), ...
                'mip:repo:conflictsWithChannel');
            testCase.verifyError(@() quietly(@() mip.install('--channel', 'myorg/tools', mhl)), ...
                'mip:repo:conflictsWithChannel');
        end

        %% Update and info

        function testUpdateFromRepoIndex(testCase)
            mhl1 = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl1)});
            evalc('mip.install(''myorg/repopkg'')');

            mhl2 = bundle(testCase, 'repopkg', '1.1.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl1), entry('repopkg', '1.1.0', mhl2)});
            evalc('mip.update(''myorg/repopkg'')');

            testCase.verifyEqual(installedVersion(testCase, 'myorg', 'repopkg'), '1.1.0');
        end

        function testUpdateBranchBuildStaysOnBranch(testCase)
            % An installed branch build (e.g. main) keeps following that
            % branch rather than switching to a numeric release.
            createTestPackage(testCase.TestRoot, 'myorg', '', 'repopkg', 'version', 'main');
            mip.state.add_directly_installed('gh/myorg/repopkg');
            mhl1 = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', 'main', mhl1), entry('repopkg', '1.0.0', mhl1)});
            out = evalc('mip.update(''myorg/repopkg'')');
            testCase.verifySubstring(out, 'already up to date (main)');
            testCase.verifyEqual(installedVersion(testCase, 'myorg', 'repopkg'), 'main');
        end

        function testInfoShowsRepository(testCase)
            mhl = bundle(testCase, 'repopkg', '1.0.0');
            writeRepoIndex(testCase.TestRoot, 'myorg/repopkg', ...
                {entry('repopkg', '1.0.0', mhl)});
            evalc('mip.install(''myorg/repopkg'')');

            out = evalc('mip.info(''myorg/repopkg'')');
            testCase.verifySubstring(out, 'myorg/repopkg');
            testCase.verifySubstring(out, 'Remote Repository: github.com/myorg/repopkg');
            testCase.verifySubstring(out, '1.0.0 (any)');
        end

        function testAvailRejectsNonRepoArgument(testCase)
            testCase.verifyError(@() mip.avail('mip-org/core/chebfun'), 'mip:avail:invalidArgs');
            testCase.verifyError(@() mip.avail('a/b', 'c/d'), 'mip:avail:invalidArgs');
        end

    end
end


function mhlPath = bundle(testCase, pkgName, version, deps)
% Build a .mhl from a generated source package.
    if nargin < 4
        deps = {};
    end
    base = fullfile(testCase.SourceDir, [pkgName '_' version]);
    mkdir(base);
    srcDir = createTestSourcePackage(base, pkgName, 'version', version, 'dependencies', deps);
    outDir = fullfile(testCase.BundleDir, [pkgName '_' version]);
    mkdir(outDir);
    evalc('mip.bundle(srcDir, ''--output'', outDir, ''--arch'', ''any'')');
    mhlFiles = dir(fullfile(outDir, '*.mhl'));
    testCase.assertNotEmpty(mhlFiles, '.mhl bundle was not produced');
    mhlPath = fullfile(outDir, mhlFiles(1).name);
end

function quietly(fn)
% Call fn with its command-window output suppressed.
    evalc('fn()');
end

function e = entry(name, version, mhlPath, deps)
    if nargin < 4
        deps = {};
    end
    e = struct('name', name, 'version', version, 'mhl_url', mhlPath);
    e.dependencies = deps;
end

function v = installedVersion(testCase, owner, repo)
    info = mip.config.read_package_json( ...
        fullfile(testCase.TestRoot, 'packages', 'gh', owner, repo));
    v = info.version;
end
