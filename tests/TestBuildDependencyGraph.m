classdef TestBuildDependencyGraph < matlab.unittest.TestCase
%TESTBUILDDEPENDENCYGRAPH   Tests for mip.dependency.build_graph,
% focusing on how bare-name dependencies are resolved to a channel using the
% fetched channel index (packageInfoMap).

    methods (Test)
        function testBareDepPrefersParentChannel(testCase)
            % A bare dep of a non-core package resolves to that package's own
            % channel when the index provides it there.
            map = makeMap( ...
                'gh/mylab/custom/parent', {'child'}, ...
                'gh/mylab/custom/child',  {});
            [depList, missing] = mip.dependency.build_graph( ...
                'gh/mylab/custom/parent', map);
            testCase.verifyEmpty(missing);
            testCase.verifyTrue(ismember('gh/mylab/custom/child', depList));
            testCase.verifyFalse(ismember('gh/mip-org/core/child', depList));
        end

        function testBareDepFallsBackToCore(testCase)
            % When the parent's own channel does not provide the dependency,
            % resolve it to mip-org/core.
            map = makeMap( ...
                'gh/mylab/custom/parent', {'child'}, ...
                'gh/mip-org/core/child',  {});
            [depList, missing] = mip.dependency.build_graph( ...
                'gh/mylab/custom/parent', map);
            testCase.verifyEmpty(missing);
            testCase.verifyTrue(ismember('gh/mip-org/core/child', depList));
        end

        function testCoreParentBareDepResolvesToCore(testCase)
            % Bare deps of a mip-org/core package resolve to mip-org/core.
            map = makeMap( ...
                'gh/mip-org/core/parent', {'child'}, ...
                'gh/mip-org/core/child',  {});
            [depList, missing] = mip.dependency.build_graph( ...
                'gh/mip-org/core/parent', map);
            testCase.verifyEmpty(missing);
            testCase.verifyTrue(ismember('gh/mip-org/core/child', depList));
        end

        function testFqnDepPreserved(testCase)
            % A fully qualified dependency is used as-is, regardless of the
            % depending package's channel.
            map = makeMap( ...
                'gh/mylab/custom/parent', {'mip-org/other/child'}, ...
                'gh/mip-org/other/child', {});
            [depList, missing] = mip.dependency.build_graph( ...
                'gh/mylab/custom/parent', map);
            testCase.verifyEmpty(missing);
            testCase.verifyTrue(ismember('gh/mip-org/other/child', depList));
        end
    end
end

function map = makeMap(varargin)
% Build a packageInfoMap from alternating (fqn, depsCell) pairs.
    map = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:2:numel(varargin)
        map(varargin{i}) = struct('dependencies', {varargin{i+1}});
    end
end
