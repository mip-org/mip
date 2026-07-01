function test(varargin)
%TEST   Run the test script for an installed package.
%
% Usage:
%   mip test <package>
%   mip test <owner>/<channel>/<package>
%
% Loads the package (if not already loaded) and runs the test script
% defined in the package's mip.yaml (test_script field). If no test
% script is defined, prints a message and returns.
%
% The test script should error on failure and print 'SUCCESS' on success.
%
% Accepts both bare package names and fully qualified names. Bare-name
% resolution prefers a currently loaded package over an installed-but-
% unloaded one; if multiple loaded packages share the bare name, the most
% recently loaded one wins. Otherwise, falls back to the installed-package
% priority (gh/mip-org/core first, then alphabetical).

if nargin < 1
    error('mip:test:noPackage', 'Package name is required for test command.');
end

packageArg = varargin{1};

r = resolveTestTarget(packageArg);
if isempty(r)
    error('mip:test:notInstalled', ...
          'Package "%s" is not installed.', packageArg);
end

displayFqn = mip.parse.display_fqn(r.fqn);

% Load the package if not already loaded
if ~mip.state.is_loaded(r.fqn)
    fprintf('Loading package "%s"...\n', displayFqn);
    mip.load(r.fqn);
end

% Find test script
pkgInfo = mip.config.read_package_json(r.pkg_dir);
testScript = mip.config.get_build_field(pkgInfo, r.pkg_dir, 'test_script');

if isempty(testScript)
    fprintf('No test script defined for package "%s".\n', displayFqn);
    return
end

% Determine test directory
testDir = mip.paths.get_source_dir(r.pkg_dir, pkgInfo);

if ~isfolder(testDir)
    error('mip:test:dirMissing', ...
          'Test directory "%s" does not exist.', testDir);
end

scriptPath = fullfile(testDir, testScript);
if ~exist(scriptPath, 'file')
    error('mip:test:scriptNotFound', ...
          'Test script not found: %s', scriptPath);
end

% Publish the fully-qualified name of the package under test so the test
% script can identify itself via mip.test.get_fqn() (and from there query
% mip.build.effective_arch / mip.build.has_mex, e.g. to skip MEX checks on a
% pure-MATLAB `any` build) without resolving its own ambiguous bare name.
% Cleared when this function returns, whether the test passes or errors.
mip.state.key_value_set('MIP_TEST_CONTEXT', r.fqn);
testCtxCleanup = onCleanup(@() mip.state.key_value_set('MIP_TEST_CONTEXT', {})); %#ok<NASGU>

fprintf('Running test script for "%s": %s\n', displayFqn, testScript);
originalDir = pwd;
try
    cd(testDir);
    run(testScript);
catch ME
    cd(originalDir);
    % Print the original error's stack so failures inside the test script
    % aren't hidden behind the mip:test:failed wrapper below.
    fprintf(2, '\nError inside test script for "%s":\n', displayFqn);
    fprintf(2, '  %s\n', ME.message);
    if ~isempty(ME.identifier)
        fprintf(2, '  (identifier: %s)\n', ME.identifier);
    end
    % ME.stack is a struct array (may be empty).  Accessing it works on
    % both numbl's wrapped struct and MATLAB's MException object.
    if ~isempty(ME.stack)
        fprintf(2, 'Call stack (most recent call first):\n');
        for k = 1:numel(ME.stack)
            frame = ME.stack(k);
            if ~isempty(frame.name)
                fprintf(2, '  at %s (%s:%d)\n', frame.name, frame.file, frame.line);
            else
                fprintf(2, '  at %s:%d\n', frame.file, frame.line);
            end
        end
    end
    fprintf(2, '\n');
    error('mip:test:failed', ...
          'Test failed for "%s": %s', displayFqn, ME.message);
end
cd(originalDir);

end

function r = resolveTestTarget(packageArg)
% Resolve a test argument to an installed package. For bare names,
% search loaded packages first and pick the most recently loaded match;
% otherwise fall back to mip.resolve.resolve_to_installed (which applies
% the gh/mip-org/core-first / alphabetical priority).

    if isstring(packageArg)
        packageArg = char(packageArg);
    end

    parsed = mip.parse.parse_package_arg(packageArg);

    if ~parsed.is_fqn
        loadedFqn = mip.resolve.resolve_to_loaded(parsed.name);
        if ~isempty(loadedFqn)
            r = mip.resolve.resolve_to_installed(loadedFqn);
            return
        end
    end

    r = mip.resolve.resolve_to_installed(packageArg);
end
