classdef TestNameEquivalence < matlab.unittest.TestCase
%TESTNAMEEQUIVALENCE   Tests for mip.name.normalize, mip.name.match, and
%   mip.resolve.installed_dir — the foundation for case- and
%   dash/underscore-insensitive package name resolution.

    properties
        OrigMipRoot
        TestRoot
    end

    methods (TestMethodSetup)
        function setupTempRoot(testCase)
            testCase.OrigMipRoot = getenv('MIP_ROOT');
            testCase.TestRoot = [tempname '_mip_test'];
            mkdir(fullfile(testCase.TestRoot, 'packages'));
            setenv('MIP_ROOT', testCase.TestRoot);
        end
    end

    methods (TestMethodTeardown)
        function restoreEnv(testCase)
            setenv('MIP_ROOT', testCase.OrigMipRoot);
            if exist(testCase.TestRoot, 'dir')
                rmdir(testCase.TestRoot, 's');
            end
        end
    end

    methods (Access = private)
        function makePkgDir(testCase, owner, channel, name)
            mkdir(fullfile(testCase.TestRoot, 'packages', 'gh', owner, channel, name));
        end
    end

    methods (Test)

        %% normalize

        function testNormalizeIdentity(testCase)
            testCase.verifyEqual(mip.name.normalize('mypkg'), 'mypkg');
        end

        function testNormalizeLowercases(testCase)
            testCase.verifyEqual(mip.name.normalize('MyPkg'), 'mypkg');
            testCase.verifyEqual(mip.name.normalize('MYPKG'), 'mypkg');
        end

        function testNormalizeDashesToUnderscores(testCase)
            testCase.verifyEqual(mip.name.normalize('my-pkg'), 'my_pkg');
            testCase.verifyEqual(mip.name.normalize('a-b-c'), 'a_b_c');
        end

        function testNormalizeMixed(testCase)
            testCase.verifyEqual(mip.name.normalize('My-Pkg'), 'my_pkg');
            testCase.verifyEqual(mip.name.normalize('MY-PKG'), 'my_pkg');
        end

        function testNormalizePreservesUnderscores(testCase)
            testCase.verifyEqual(mip.name.normalize('my_pkg'), 'my_pkg');
        end

        function testNormalizeAcceptsString(testCase)
            testCase.verifyEqual(mip.name.normalize("My-Pkg"), 'my_pkg');
        end

        function testNormalizeRejectsNonString(testCase)
            testCase.verifyError(@() mip.name.normalize(42), ...
                'mip:name:invalidInput');
        end

        %% match

        function testMatchIdentity(testCase)
            testCase.verifyTrue(mip.name.match('foo', 'foo'));
        end

        function testMatchCaseInsensitive(testCase)
            testCase.verifyTrue(mip.name.match('foo', 'FOO'));
            testCase.verifyTrue(mip.name.match('MyPkg', 'mypkg'));
        end

        function testMatchDashUnderscoreEquivalent(testCase)
            testCase.verifyTrue(mip.name.match('my-pkg', 'my_pkg'));
            testCase.verifyTrue(mip.name.match('a-b-c', 'a_b_c'));
        end

        function testMatchCombined(testCase)
            testCase.verifyTrue(mip.name.match('My-Pkg', 'my_pkg'));
            testCase.verifyTrue(mip.name.match('MY-PKG', 'my_pkg'));
        end

        function testMatchSeparatorPresenceMatters(testCase)
            % Normalization equates - and _, but does NOT remove them.
            % mypkg and my-pkg are different names.
            testCase.verifyFalse(mip.name.match('mypkg', 'my-pkg'));
            testCase.verifyFalse(mip.name.match('mypkg', 'my_pkg'));
        end

        function testMatchDifferent(testCase)
            testCase.verifyFalse(mip.name.match('foo', 'bar'));
            testCase.verifyFalse(mip.name.match('mypkg', 'mypkg2'));
        end

        function testMatchAcceptsString(testCase)
            testCase.verifyTrue(mip.name.match("My-Pkg", "my_pkg"));
        end

        function testMatchEmpty(testCase)
            testCase.verifyTrue(mip.name.match('', ''));
            testCase.verifyFalse(mip.name.match('', 'foo'));
        end

        %% installed_dir

        function testInstalledDirExactMatch(testCase)
            testCase.makePkgDir('mip-org', 'core', 'chebfun');
            testCase.verifyEqual( ...
                mip.resolve.installed_dir('gh/mip-org/core/chebfun'), ...
                'chebfun');
        end

        function testInstalledDirCaseInsensitive(testCase)
            testCase.makePkgDir('mip-org', 'core', 'ChebFun');
            testCase.verifyEqual( ...
                mip.resolve.installed_dir('gh/mip-org/core/chebfun'), ...
                'ChebFun');
        end

        function testInstalledDirDashUnderscore(testCase)
            testCase.makePkgDir('mip-org', 'core', 'my-pkg');
            testCase.verifyEqual( ...
                mip.resolve.installed_dir('gh/mip-org/core/my_pkg'), ...
                'my-pkg');
        end

        function testInstalledDirCombined(testCase)
            testCase.makePkgDir('mip-org', 'core', 'My-Pkg');
            testCase.verifyEqual( ...
                mip.resolve.installed_dir('gh/mip-org/core/MY_PKG'), ...
                'My-Pkg');
        end

        function testInstalledDirNotFound(testCase)
            testCase.verifyEqual( ...
                mip.resolve.installed_dir('gh/mip-org/core/nonexistent'), ...
                '');
        end

        function testInstalledDirMissingChannel(testCase)
            testCase.verifyEqual( ...
                mip.resolve.installed_dir('gh/mip-org/missing/x'), ...
                '');
        end

        %% build_package_info_map

        function testBuildPackageInfoMap_DifferentNamesNotMerged(testCase)
            % Names that are not equivalent under mip.name.match stay
            % separate. `mypkg` (no separator) and `my-pkg` (with dash)
            % normalize to different forms and must not be merged.
            pkg1 = struct('name', 'mypkg',  'version', '1.0', 'architecture', 'any');
            pkg2 = struct('name', 'my-pkg', 'version', '1.0', 'architecture', 'any');
            index = struct('packages', {{pkg1, pkg2}});

            m = mip.resolve.build_package_info_map(index, 'mip-org', 'core');

            testCase.verifyEqual(m.Count, uint64(2));
            testCase.verifyTrue(m.isKey('gh/mip-org/core/mypkg'));
            testCase.verifyTrue(m.isKey('gh/mip-org/core/my-pkg'));
        end

    end
end
