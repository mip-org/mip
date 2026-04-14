classdef TestMatchBuild < matlab.unittest.TestCase
%TESTMATCHBUILD   Tests for mip.build.match_build.

    methods (Test)

        function testExactMatch(testCase)
            cfg = makeConfig({{'linux_x86_64'}});
            [b, arch] = mip.build.match_build(cfg, 'linux_x86_64');
            testCase.verifyEqual(arch, 'linux_x86_64');
            testCase.verifyEqual(b.architectures, {'linux_x86_64'});
        end

        function testAnyFallback(testCase)
            cfg = makeConfig({{'any'}});
            [b, arch] = mip.build.match_build(cfg, 'linux_x86_64');
            testCase.verifyEqual(arch, 'any');
            testCase.verifyEqual(b.architectures, {'any'});
        end

        function testExactPreferredOverAny_AnyFirst(testCase)
            % 'any' build listed before exact match — exact should still win.
            cfg = makeConfig({{'any'}, {'linux_x86_64'}});
            [~, arch] = mip.build.match_build(cfg, 'linux_x86_64');
            testCase.verifyEqual(arch, 'linux_x86_64');
        end

        function testExactPreferredOverAny_ExactFirst(testCase)
            % Exact match listed first — should still work.
            cfg = makeConfig({{'linux_x86_64'}, {'any'}});
            [~, arch] = mip.build.match_build(cfg, 'linux_x86_64');
            testCase.verifyEqual(arch, 'linux_x86_64');
        end

        function testNoMatch(testCase)
            cfg = makeConfig({{'macos_arm64'}});
            testCase.verifyError( ...
                @() mip.build.match_build(cfg, 'linux_x86_64'), ...
                'mip:noMatchingBuild');
        end

        function testNoBuilds(testCase)
            cfg = struct('builds', {{}});
            testCase.verifyError( ...
                @() mip.build.match_build(cfg, 'linux_x86_64'), ...
                'mip:noBuild');
        end

        function testMultiArchBuild(testCase)
            % A single build entry listing multiple architectures.
            cfg = makeConfig({{'linux_x86_64', 'macos_arm64'}});
            [~, arch] = mip.build.match_build(cfg, 'macos_arm64');
            testCase.verifyEqual(arch, 'macos_arm64');
        end

        function testMultipleBuilds_CorrectEntryReturned(testCase)
            % Verify the correct build entry (not just arch) is returned.
            cfg = struct('builds', {{...
                struct('architectures', {{'any'}}, 'compile_script', 'generic.m'), ...
                struct('architectures', {{'linux_x86_64'}}, 'compile_script', 'linux.m') ...
            }});
            [b, arch] = mip.build.match_build(cfg, 'linux_x86_64');
            testCase.verifyEqual(arch, 'linux_x86_64');
            testCase.verifyEqual(b.compile_script, 'linux.m');
        end

        function testFallsBackToAnyWhenNoExact(testCase)
            % No exact match among multiple builds — should fall back to 'any'.
            cfg = makeConfig({{'macos_arm64'}, {'any'}});
            [~, arch] = mip.build.match_build(cfg, 'linux_x86_64');
            testCase.verifyEqual(arch, 'any');
        end

        function testFirstAnyBuildSelectedOnFallback(testCase)
            % When falling back, the first 'any' build wins.
            cfg = struct('builds', {{...
                struct('architectures', {{'macos_arm64'}}, 'compile_script', 'mac.m'), ...
                struct('architectures', {{'any'}}, 'compile_script', 'first_any.m'), ...
                struct('architectures', {{'any'}}, 'compile_script', 'second_any.m') ...
            }});
            [b, ~] = mip.build.match_build(cfg, 'linux_x86_64');
            testCase.verifyEqual(b.compile_script, 'first_any.m');
        end

    end
end

function cfg = makeConfig(archLists)
% Helper: build a mipConfig struct with builds having the given architecture lists.
    builds = cell(1, length(archLists));
    for i = 1:length(archLists)
        builds{i} = struct('architectures', {archLists{i}});
    end
    cfg = struct('builds', {builds});
end
