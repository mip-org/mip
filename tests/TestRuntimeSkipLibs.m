classdef TestRuntimeSkipLibs < matlab.unittest.TestCase
%TESTRUNTIMESKIPLIBS   Tests for mip.build.runtime_skip_libs.
%
% The deny-lists decide which of a MEX's dynamic dependencies
% bundle_runtime_libs vendors. MATLAB-provided libraries (libmx/libmex and
% the MATLAB BLAS/LAPACK) must be skipped: vendoring libmwblas/libmwlapack
% warns-and-skips on Linux but hard-fails the copy on macOS (their
% LC_LOAD_DYLIB is @rpath/libmwblas.dylib, with no on-disk path).

    methods (Test)
        function returnsBothLists(testCase)
            [linuxSonames, macPrefixes] = mip.build.runtime_skip_libs();
            testCase.verifyClass(linuxSonames, 'cell');
            testCase.verifyClass(macPrefixes, 'cell');
            testCase.verifyNotEmpty(linuxSonames);
            testCase.verifyNotEmpty(macPrefixes);
        end

        function skipsMatlabBlasLapackLinux(testCase)
            linuxSonames = mip.build.runtime_skip_libs();
            testCase.verifyTrue(ismember('libmwblas.so', linuxSonames));
            testCase.verifyTrue(ismember('libmwlapack.so', linuxSonames));
        end

        function skipsMatlabBlasLapackMacos(testCase)
            [~, macPrefixes] = mip.build.runtime_skip_libs();
            testCase.verifyTrue(ismember('@rpath/libmwblas.', macPrefixes));
            testCase.verifyTrue(ismember('@rpath/libmwlapack.', macPrefixes));
        end

        function stillSkipsCoreMatlabAndSystemLibs(testCase)
            % Guard against accidental removal of the pre-existing entries.
            [linuxSonames, macPrefixes] = mip.build.runtime_skip_libs();
            for so = {'libc.so.6', 'libstdc++.so.6', 'libgfortran.so.5', ...
                      'libmx.so', 'libmex.so'}
                testCase.verifyTrue(ismember(so{1}, linuxSonames), ...
                    sprintf('expected %s in Linux skip list', so{1}));
            end
            for p = {'/usr/lib/', '@rpath/libmx.', '@rpath/libmex.'}
                testCase.verifyTrue(ismember(p{1}, macPrefixes), ...
                    sprintf('expected %s in macOS skip prefixes', p{1}));
            end
        end

        function doesNotSkipLoadBearingLibgomp(testCase)
            % libgomp is intentionally NOT skipped on Linux (MATLAB does not
            % ship it, so the bundled copy is load-bearing).
            linuxSonames = mip.build.runtime_skip_libs();
            testCase.verifyFalse(ismember('libgomp.so.1', linuxSonames));
        end
    end
end
