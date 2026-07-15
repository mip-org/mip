classdef TestProjectWorkflow < matlab.unittest.TestCase
%TESTPROJECTWORKFLOW   Tests for "mip project init" (incl. --from-env),
%   "mip project status" (modes, drift, --check), "mip project run"
%   (scoped activation, targets, --locked), and the no-argument
%   "mip activate" project walk.

    properties
        OrigMipRoot
        TestRoot
        WorkDir
        SourceDir
        BundleDir
        OrigPwd
        OrigPath
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_proj_wf_root'];
            testCase.WorkDir = [tempname '_mip_proj_wf_work'];
            testCase.SourceDir = [tempname '_mip_proj_wf_src'];
            testCase.BundleDir = [tempname '_mip_proj_wf_bundle'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            mkdir(testCase.SourceDir);
            mkdir(testCase.BundleDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.OrigPwd = pwd;
            testCase.OrigPath = path;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigPwd);
            path(testCase.OrigPath);
            cleanupTestPaths(testCase.TestRoot);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            dirs = {testCase.TestRoot, testCase.WorkDir, ...
                    testCase.SourceDir, testCase.BundleDir};
            for d = dirs
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        % ---- init ----

        function testInitCreatesNamelessSpec(testCase)
            cd(testCase.WorkDir);
            evalc('mip.project.init()');
            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(spec.name, '');
            testCase.verifyEmpty(spec.dependencies);
            testCase.verifyFalse(isfile(fullfile(testCase.WorkDir, 'mip.lock')), ...
                'init must not opt the directory into uv mode');

            testCase.verifyError(@() evalc('mip.project.init()'), ...
                'mip:project:specExists');
        end

        function testInitFromEnv(testCase)
            % The active root has two directly installed channel packages,
            % one transitive dep, and one local install (skipped).
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'pkga');
            createTestPackage(testCase.TestRoot, 'mylab', 'custom', 'labpkg');
            createTestPackage(testCase.TestRoot, 'mip-org', 'core', 'transdep');
            createTestPackage(testCase.TestRoot, '', '', 'devpkg', 'type', 'local');
            mip.state.add_directly_installed('gh/mip-org/core/pkga');
            mip.state.add_directly_installed('gh/mylab/custom/labpkg');
            mip.state.add_directly_installed('local/devpkg');

            cd(testCase.WorkDir);
            output = evalc('mip.project.init(''--from-env'')');

            spec = mip.project.read_spec(testCase.WorkDir);
            testCase.verifyEqual(sort(spec.dependencies), ...
                {'mylab/custom/labpkg', 'pkga'}, ...
                ['--from-env records direct installs: bare names for core, ' ...
                 'display FQNs otherwise; names only, no pins']);
            testCase.verifyTrue(contains(output, 'skipping "local/devpkg"'), ...
                'non-channel installs are skipped with a note');
        end

        % ---- status ----

        function testStatusModesAndDrift(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);

            % pip+venv mode: no lock.
            output = evalc('mip.project.status()');
            testCase.verifyTrue(contains(output, 'mode: pip+venv'));
            testCase.verifyTrue(contains(output, 'status: ok'));

            % Locked but never synced: drift.
            evalc('mip.project.lock()');
            output = evalc('mip.project.status()');
            testCase.verifyTrue(contains(output, 'mode: uv'));
            testCase.verifyTrue(contains(output, 'drift:'));
            testCase.verifyError(@() evalc('mip.project.status(''--check'')'), ...
                'mip:project:drift');

            % Synced: ok.
            evalc('mip.project.sync()');
            output = evalc('mip.project.status()');
            testCase.verifyTrue(contains(output, 'status: ok'));

            % Spec edited: stale vs lock.
            mip.project.edit_spec(fullfile(testCase.WorkDir, 'mip.yaml'), ...
                                  '', {'pkga@1.0.0'}, {});
            if ~isempty(mip.project.spec_hash(testCase.WorkDir))
                output = evalc('mip.project.status()');
                testCase.verifyTrue(contains(output, 'spec vs lock: STALE'));
                testCase.verifyError(@() evalc('mip.project.status(''--check'')'), ...
                    'mip:project:drift');
            end

            % Unrecorded package in the env: drift.
            evalc('mip.project.lock()');
            evalc('mip.project.sync()');
            createTestPackage(fullfile(testCase.WorkDir, '.mip'), ...
                              'mip-org', 'core', 'strayp');
            output = evalc('mip.project.status()');
            testCase.verifyTrue(contains(output, 'unrecorded package'));
        end

        % ---- run ----

        function testRunScriptScopedActivation(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');

            probePath = fullfile(testCase.WorkDir, 'probe.m');
            outPath = fullfile(testCase.WorkDir, 'probe_out.txt');
            writeLines(probePath, { ...
                'fid = fopen(fullfile(fileparts(mfilename(''fullpath'')), ''probe_out.txt''), ''w'');', ...
                'fprintf(fid, ''root=%s\n'', getenv(''MIP_ROOT''));', ...
                'fprintf(fid, ''pkga=%d\n'', exist(''pkga'', ''file''));', ...
                'fclose(fid);'});

            evalc('mip.project.run(''probe.m'')');

            testCase.assertTrue(isfile(outPath), 'the probe script must have run');
            out = fileread(outPath);
            testCase.verifyTrue(contains(out, ...
                ['root=' fullfile(testCase.WorkDir, '.mip')]), ...
                'the project env must be the active root during the run');
            testCase.verifyTrue(contains(out, 'pkga=2'), ...
                'the locked package must be loaded during the run');

            % The session is restored afterwards.
            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot);
            testCase.verifyEmpty(mip.state.get_active_env());
            loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
            testCase.verifyEqual(loaded, {'gh/mip-org/core/mip'}, ...
                'only mip itself stays loaded after the run');
            testCase.verifyFalse(contains(path, fullfile(testCase.WorkDir, '.mip')), ...
                'no env path entries may survive the run');
        end

        function testRunFunctionAndExpressionTargets(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');

            writeLines(fullfile(testCase.WorkDir, 'probefun.m'), { ...
                'function probefun(arg)', ...
                'fid = fopen(''probefun_out.txt'', ''w'');', ...
                'fprintf(fid, ''%s:%s'', class(arg), arg);', ...
                'fclose(fid);', ...
                'end'});

            evalc('mip.project.run(''probefun'', ''3'')');
            testCase.assertTrue(isfile(fullfile(testCase.WorkDir, 'probefun_out.txt')));
            testCase.verifyEqual(fileread(fullfile(testCase.WorkDir, 'probefun_out.txt')), ...
                'char:3', 'command-syntax arguments must arrive as char');

            evalc('mip.project.run(''fid = fopen(''''expr_out.txt'''', ''''w''''); fclose(fid);'')');
            testCase.verifyTrue(isfile(fullfile(testCase.WorkDir, 'expr_out.txt')), ...
                'the expression target must execute');
        end

        function testRunLockedErrorsWhenStale(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);

            % No lock at all: --locked errors.
            testCase.verifyError(@() evalc('mip.project.run(''--locked'', ''x = 1;'')'), ...
                'mip:project:lockStale');

            evalc('mip.project.lock()');
            if isempty(mip.project.spec_hash(testCase.WorkDir))
                return  % no JVM: staleness cannot be detected
            end
            writeSpec(testCase, {'dependencies: []'});
            testCase.verifyError(@() evalc('mip.project.run(''--locked'', ''x = 1;'')'), ...
                'mip:project:lockStale');
        end

        function testRunRestoresOnTargetError(testCase)
            indexWithBundles(testCase, {'pkga'});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            evalc('mip.project.lock()');

            testCase.verifyError(...
                @() evalc('mip.project.run(''error(''''boom:boom'''', ''''boom'''')'')'), ...
                'boom:boom');
            testCase.verifyEqual(getenv('MIP_ROOT'), testCase.TestRoot, ...
                'the root pointer must be restored when the target errors');
            testCase.verifyEmpty(mip.state.get_active_env());
        end

        % ---- no-argument activate walks to the project ----

        function testActivateNoArgWalksToProject(testCase)
            writeSpec(testCase, {'dependencies: []'});
            envPath = fullfile(testCase.WorkDir, '.mip');
            mip.env.materialize(envPath);
            nested = fullfile(testCase.WorkDir, 'sub');
            mkdir(nested);
            cd(nested);

            evalc('mip.activate()');
            restoreEnv = onCleanup(@() evalc('mip.deactivate()')); %#ok<NASGU>

            env = mip.state.get_active_env();
            testCase.assertNotEmpty(env);
            testCase.verifyEqual(env.path, envPath, ...
                'no-argument activate must walk up to the nearest project''s .mip');
        end

    end
end

function indexWithBundles(testCase, names)
    entries = cell(1, numel(names));
    for i = 1:numel(names)
        [mhlUrl, sha] = bundlePackage(testCase, names{i});
        entries{i} = struct('name', names{i}, 'version', '1.0.0', ...
                            'mhl_url', mhlUrl, 'mhl_sha256', sha);
    end
    writeChannelIndex(testCase.TestRoot, 'mip-org/core', entries);
end

function [mhlUrl, sha] = bundlePackage(testCase, pkgName)
    srcDir = createTestSourcePackage(testCase.SourceDir, pkgName); %#ok<NASGU> (used inside evalc)
    evalc('mip.bundle(srcDir, ''--output'', testCase.BundleDir, ''--arch'', ''any'')');
    mhlFiles = dir(fullfile(testCase.BundleDir, [pkgName '-*.mhl']));
    testCase.assertNotEmpty(mhlFiles, '.mhl bundle was not produced');
    mhlUrl = fullfile(testCase.BundleDir, mhlFiles(1).name);
    sha = mip.channel.sha256(mhlUrl);
end

function writeSpec(testCase, lines)
    writeLines(fullfile(testCase.WorkDir, 'mip.yaml'), lines);
end

function writeLines(p, lines)
    fid = fopen(p, 'w');
    fwrite(fid, [strjoin(lines, newline) newline]);
    fclose(fid);
end
