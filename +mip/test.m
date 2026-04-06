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
if isstring(packageArg)
    packageArg = char(packageArg);
end

% Resolve to FQN
result = mip.utils.parse_package_arg(packageArg);

if result.is_fqn
    fqn = packageArg;
    org = result.org;
    channelName = result.channel;
    packageName = result.name;
else
    fqn = mip.utils.resolve_bare_name(result.name);
    if isempty(fqn)
        error('mip:test:notInstalled', ...
              'Package "%s" is not installed.', result.name);
    end
    r = mip.utils.parse_package_arg(fqn);
    org = r.org;
    channelName = r.channel;
    packageName = r.name;
end

pkgDir = mip.utils.get_package_dir(org, channelName, packageName);

if ~exist(pkgDir, 'dir')
    error('mip:test:notInstalled', ...
          'Package "%s" is not installed.', fqn);
end

% Load the package if not already loaded
if ~mip.utils.is_loaded(fqn)
    fprintf('Loading package "%s"...\n', fqn);
    mip.load(fqn);
end

% Determine test script
testScript = '';

% First check mip.json (editable installs may store it there)
pkgInfo = mip.utils.read_package_json(pkgDir);
if isfield(pkgInfo, 'test_script') && ~isempty(pkgInfo.test_script)
    testScript = pkgInfo.test_script;
end

% If not in mip.json, try reading from mip.yaml
if isempty(testScript)
    yamlSearchDir = pkgDir;
    if isfield(pkgInfo, 'source_path') && ~isempty(pkgInfo.source_path) ...
            && isfolder(pkgInfo.source_path)
        yamlSearchDir = pkgInfo.source_path;
    end

    mipYamlPath = fullfile(yamlSearchDir, 'mip.yaml');
    if isfile(mipYamlPath)
        mipConfig = mip.utils.read_mip_yaml(yamlSearchDir);
        [buildEntry, ~] = mip.build.match_build(mipConfig);
        resolvedConfig = mip.build.resolve_build_config(mipConfig, buildEntry);
        if isfield(resolvedConfig, 'test_script') && ~isempty(resolvedConfig.test_script)
            testScript = resolvedConfig.test_script;
        end
    end
end

if isempty(testScript)
    fprintf('No test script defined for package "%s".\n', fqn);
    return
end

% Determine test directory
if isfield(pkgInfo, 'source_path') && ~isempty(pkgInfo.source_path) ...
        && isfolder(pkgInfo.source_path)
    testDir = pkgInfo.source_path;
else
    testDir = fullfile(pkgDir, pkgInfo.name);
end

if ~isfolder(testDir)
    error('mip:test:dirMissing', ...
          'Test directory "%s" does not exist.', testDir);
end

scriptPath = fullfile(testDir, testScript);
if ~exist(scriptPath, 'file')
    error('mip:test:scriptNotFound', ...
          'Test script not found: %s', scriptPath);
end

fprintf('Running test script for "%s": %s\n', fqn, testScript);
originalDir = pwd;
try
    cd(testDir);
    run(testScript);
catch ME
    cd(originalDir);
    error('mip:test:failed', ...
          'Test failed for "%s": %s', fqn, ME.message);
end
cd(originalDir);

end
