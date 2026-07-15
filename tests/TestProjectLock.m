classdef TestProjectLock < matlab.unittest.TestCase
%TESTPROJECTLOCK   Tests for "mip project lock" (mip.project.lock_project):
%   resolution against fake channel indexes, dependency closure, groups,
%   @version pins, version preservation vs --upgrade, and lock contents.

    properties
        OrigMipRoot
        TestRoot
        WorkDir
        OrigPwd
    end

    methods (TestMethodSetup)
        function setupTestEnvironment(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_proj_lock_root'];
            testCase.WorkDir = [tempname '_mip_proj_lock_work'];
            mkdir(testCase.TestRoot);
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            mkdir(testCase.WorkDir);
            setenv('MIP_ROOT', testCase.TestRoot);
            testCase.OrigPwd = pwd;
            clearMipState();
        end
    end

    methods (TestMethodTeardown)
        function teardownTestEnvironment(testCase)
            cd(testCase.OrigPwd);
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            for d = {testCase.TestRoot, testCase.WorkDir}
                if exist(d{1}, 'dir')
                    rmdir(d{1}, 's');
                end
            end
            clearMipState();
        end
    end

    methods (Test)

        function testLockResolvesClosureDependencyFirst(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'dependencies', {{'pkgb'}}, ...
                       'mhl_sha256', 'aaa1'), ...
                struct('name', 'pkgb', 'commit_hash', 'c0ffee')});
            writeSpec(testCase, {'dependencies: [pkga]'});

            lockData = lockHere(testCase);

            testCase.verifyEqual(numel(lockData.packages), 2);
            testCase.verifyEqual(lockData.packages{1}.fqn, 'gh/mip-org/core/pkgb', ...
                'the lock must be in dependency-first order');
            testCase.verifyEqual(lockData.packages{2}.fqn, 'gh/mip-org/core/pkga');
            testCase.verifyTrue(lockData.packages{2}.direct);
            testCase.verifyFalse(lockData.packages{1}.direct);
            testCase.verifyTrue(lockData.packages{1}.base);
            testCase.verifyEqual(lockData.packages{2}.mhl_sha256, 'aaa1', ...
                'the digest is copied from the channel index');
            testCase.verifyEqual(lockData.packages{1}.commit_hash, 'c0ffee');
            testCase.verifyTrue(isfile(fullfile(testCase.WorkDir, 'mip.lock')));

            % The lock records the spec hash for staleness detection.
            testCase.verifyEqual(lockData.spec_sha256, ...
                mip.project.spec_hash(testCase.WorkDir));
        end

        function testLockLocksAllGroupsAndMarksThem(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', ...
                {'pkga', 'pkgtest', 'pkgdocs'});
            writeSpec(testCase, { ...
                'dependencies: [pkga]', ...
                'dependency_groups:', ...
                '  dev:', ...
                '    - pkgtest', ...
                '  docs:', ...
                '    - pkgdocs'});

            lockData = lockHere(testCase);

            entries = entryMap(lockData);
            testCase.verifyTrue(entries('gh/mip-org/core/pkga').base);
            testCase.verifyEmpty(entries('gh/mip-org/core/pkga').groups);
            testCase.verifyFalse(entries('gh/mip-org/core/pkgtest').base);
            testCase.verifyEqual(entries('gh/mip-org/core/pkgtest').groups, {'dev'});
            testCase.verifyEqual(entries('gh/mip-org/core/pkgdocs').groups, {'docs'});
            testCase.verifyTrue(entries('gh/mip-org/core/pkgtest').direct, ...
                'group members named in the spec are direct');
        end

        function testLockHonorsVersionPins(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'version', '1.0.0'), ...
                struct('name', 'pkga', 'version', '2.0.0')});
            writeSpec(testCase, {'dependencies: [pkga@1.0.0]'});

            lockData = lockHere(testCase);
            testCase.verifyEqual(lockData.packages{1}.version, '1.0.0');
        end

        function testLockConflictingPinsError(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'version', '1.0.0'), ...
                struct('name', 'pkga', 'version', '2.0.0')});
            writeSpec(testCase, { ...
                'dependencies: [pkga@1.0.0]', ...
                'dependency_groups:', ...
                '  dev:', ...
                '    - pkga@2.0.0'});
            cd(testCase.WorkDir);
            testCase.verifyError(@() evalc('mip.project.lock()'), ...
                'mip:project:conflictingPins');
        end

        function testLockPreservesVersionsUnlessUpgrade(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'version', '1.0.0')});
            writeSpec(testCase, {'dependencies: [pkga]'});
            lockHere(testCase);

            % The channel now publishes 2.0.0 as well; a plain re-lock
            % keeps 1.0.0, --upgrade moves to 2.0.0.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'version', '1.0.0'), ...
                struct('name', 'pkga', 'version', '2.0.0')});

            lockData = lockHere(testCase);
            testCase.verifyEqual(lockData.packages{1}.version, '1.0.0', ...
                'a plain re-lock keeps locked versions the channel still publishes');

            lockData = lockHere(testCase, '--upgrade');
            testCase.verifyEqual(lockData.packages{1}.version, '2.0.0', ...
                '--upgrade re-resolves to the newest permitted version');
        end

        function testLockSpecChannels(testCase)
            % A bare name missing from core resolves against the spec's
            % channels, in order, after mip-org/core.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {'pkga'});
            writeChannelIndex(testCase.TestRoot, 'mylab/custom', {'labpkg'});
            writeSpec(testCase, { ...
                'dependencies:', ...
                '  - pkga', ...
                '  - labpkg', ...
                'channels:', ...
                '  - mylab/custom'});

            lockData = lockHere(testCase);
            entries = entryMap(lockData);
            testCase.verifyTrue(entries.isKey('gh/mip-org/core/pkga'));
            testCase.verifyTrue(entries.isKey('gh/mylab/custom/labpkg'));
        end

        function testLockFetchesCrossChannelDependency(testCase)
            % A core package depending on an FQN in another channel: the
            % dependency's channel index is fetched on demand and the
            % dependency lands in the closure.
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', { ...
                struct('name', 'pkga', 'dependencies', {{'mylab/custom/labdep'}})});
            writeChannelIndex(testCase.TestRoot, 'mylab/custom', {'labdep'});
            writeSpec(testCase, {'dependencies: [pkga]'});

            lockData = lockHere(testCase);

            entries = entryMap(lockData);
            testCase.verifyTrue(entries.isKey('gh/mylab/custom/labdep'), ...
                'the cross-channel dependency must be locked');
            testCase.verifyTrue(entries('gh/mylab/custom/labdep').base);
            testCase.verifyFalse(entries('gh/mylab/custom/labdep').direct);
            testCase.verifyEqual(lockData.packages{1}.fqn, 'gh/mylab/custom/labdep', ...
                'dependency-first order');
        end

        function testLockRejectsNonChannelDependency(testCase)
            writeSpec(testCase, {'dependencies: [local/mypkg]'});
            cd(testCase.WorkDir);
            testCase.verifyError(@() evalc('mip.project.lock()'), ...
                'mip:project:unsupportedDependency');
        end

        function testLockPackageNotFoundErrors(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {'pkga'});
            writeSpec(testCase, {'dependencies: [nosuchpkg]'});
            cd(testCase.WorkDir);
            testCase.verifyError(@() evalc('mip.project.lock()'), ...
                'mip:packageNotFound');
        end

        function testLockEmptySpec(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {});
            writeSpec(testCase, {'dependencies: []'});
            lockData = lockHere(testCase);
            testCase.verifyEmpty(lockData.packages);
        end

        function testLockViaDispatcher(testCase)
            writeChannelIndex(testCase.TestRoot, 'mip-org/core', {'pkga'});
            writeSpec(testCase, {'dependencies: [pkga]'});
            cd(testCase.WorkDir);
            evalc('mip project lock');
            testCase.verifyTrue(isfile(fullfile(testCase.WorkDir, 'mip.lock')));
        end

    end
end

function lockData = lockHere(testCase, varargin)
    cd(testCase.WorkDir);
    args = varargin; %#ok<NASGU>
    evalc('mip.project.lock(args{:})');
    lockData = mip.project.read_lock(fullfile(testCase.WorkDir, 'mip.lock'));
end

function m = entryMap(lockData)
    m = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:numel(lockData.packages)
        m(lockData.packages{i}.fqn) = lockData.packages{i};
    end
end

function writeSpec(testCase, lines)
    fid = fopen(fullfile(testCase.WorkDir, 'mip.yaml'), 'w');
    fwrite(fid, [strjoin(lines, newline) newline]);
    fclose(fid);
end
