function test(varargin)
%TEST   Run the test script for an installed package.
%
% Usage:
%   mip.test('packageName')
%   mip.test('org/channel/packageName')
%
% Loads the package (if not already loaded) and runs the test script
% defined in the package's mip.yaml (test_script field). If no test
% script is defined, prints a message and returns.
%
% The test script should error on failure and print 'SUCCESS' on success.
%
% Accepts both bare package names and fully qualified names.

if nargin < 1
    error('mip:test:noPackage', 'Package name is required for test command.');
end

packageArg = varargin{1};

% Resolve to installed FQN
r = mip.resolve.resolve_to_installed(packageArg);
if isempty(r)
    error('mip:test:notInstalled', ...
          'Package "%s" is not installed.', packageArg);
end

% Load the package if not already loaded
if ~mip.state.is_loaded(r.fqn)
    fprintf('Loading package "%s"...\n', r.fqn);
    mip.load(r.fqn);
end

% Find test script
pkgInfo = mip.config.read_package_json(r.pkg_dir);
testScript = mip.config.get_build_field(pkgInfo, r.pkg_dir, 'test_script');

if isempty(testScript)
    fprintf('No test script defined for package "%s".\n', r.fqn);
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

fprintf('Running test script for "%s": %s\n', r.fqn, testScript);
originalDir = pwd;
try
    cd(testDir);
    run(testScript);
catch ME
    cd(originalDir);
    % Print the original error's stack so failures inside the test script
    % aren't hidden behind the mip:test:failed wrapper below.
    fprintf(2, '\nError inside test script for "%s":\n', r.fqn);
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
          'Test failed for "%s": %s', r.fqn, ME.message);
end
cd(originalDir);

end
