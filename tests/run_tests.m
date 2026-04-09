function results = run_tests()
%RUN_TESTS   Run all mip unit tests.
%
% Usage:
%   results = run_tests();
%
% Returns:
%   results - TestResult array from MATLAB's testing framework

import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.DiagnosticsValidationPlugin

% Get the directory containing this script
testDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(testDir);

% Add repo root, test dir, and helpers to path (repo root must be first
% so the correct +mip package is found regardless of current directory)
helpersDir = fullfile(testDir, 'helpers');
addpath(repoRoot);
addpath(testDir);
addpath(helpersDir);

% Restore path on exit
cleanupObj = onCleanup(@() rmpath(helpersDir, testDir, repoRoot));

% Build test suite from explicit test classes
suite = [ ...
    TestSuite.fromClass(?TestUtilsParsing), ...
    TestSuite.fromClass(?TestParseYaml), ...
    TestSuite.fromClass(?TestKeyValueStorage), ...
    TestSuite.fromClass(?TestPackageDiscovery), ...
    TestSuite.fromClass(?TestReadMipYaml), ...
    TestSuite.fromClass(?TestLoadPackage), ...
    TestSuite.fromClass(?TestUnloadPackage), ...
    TestSuite.fromClass(?TestMipIdentity), ...
    TestSuite.fromClass(?TestInstallLocal), ...
    TestSuite.fromClass(?TestUninstallPackage), ...
    TestSuite.fromClass(?TestInfoPackage), ...
    TestSuite.fromClass(?TestUpdateLocal), ...
    TestSuite.fromClass(?TestCompile), ...
];

% Add remote/channel tests unless MIP_SKIP_REMOTE is set
if isempty(getenv('MIP_SKIP_REMOTE'))
    suite = [suite, ...
        TestSuite.fromClass(?TestInstallRemote), ...
        TestSuite.fromClass(?TestUpdateRemote)];
end

% Run tests
runner = TestRunner.withTextOutput('Verbosity', 3);
results = runner.run(suite);

% Print summary
fprintf('\n=== Test Summary ===\n');
fprintf('  Total:   %d\n', length(results));
fprintf('  Passed:  %d\n', sum([results.Passed]));
fprintf('  Failed:  %d\n', sum([results.Failed]));
fprintf('  Errors:  %d\n', sum([results.Incomplete]));

if all([results.Passed])
    fprintf('\nAll tests passed.\n');
else
    fprintf('\nSome tests failed. See details above.\n');
    % Print failed test names
    failedIdx = find(~[results.Passed]);
    for i = 1:length(failedIdx)
        fprintf('  FAILED: %s\n', results(failedIdx(i)).Name);
    end
end

end
