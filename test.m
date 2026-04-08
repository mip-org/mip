% Test script for the mip package.
% Invoked by `mip test mip`. Runs the unit tests in tests/run_tests.m,
% errors if any test failed, and prints SUCCESS otherwise.

scriptDir = fileparts(mfilename('fullpath'));
testsDir = fullfile(scriptDir, 'tests');

addpath(testsDir);

results = run_tests();

if isempty(results) || ~all([results.Passed])
    error('mip:test:failed', 'One or more mip unit tests failed.');
end

fprintf('SUCCESS\n');
