% Test script for the mip package.
% Invoked by `mip test mip`. Runs the unit tests in run_tests.m,
% errors if any test failed, and prints SUCCESS otherwise.

results = run_tests();

if isempty(results) || ~all([results.Passed])
    error('mip:test:failed', 'One or more mip unit tests failed.');
end

fprintf('SUCCESS\n');
