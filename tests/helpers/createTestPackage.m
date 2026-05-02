function pkgDir = createTestPackage(rootDir, owner, channel, pkgName, varargin)
%CREATETESTPACKAGE   Create a fake installed mip package for testing.
%
% The on-disk layout follows the canonical mip layout:
%   - For GitHub channel packages (3-arg form): owner/channel/name are
%     provided. The package is created at
%     <rootDir>/packages/gh/<owner>/<channel>/<name>/.
%   - For non-gh source types (2-arg form): the second positional arg
%     is the package name, with owner/channel omitted or passed as ''.
%     Pass source-type via the 'type' name-value ('local' or 'fex').
%
% The package is created with a "paths" field in mip.json that points at
% the pkgDir/<name>/ source subdirectory.
%
% Args:
%   rootDir  - The MIP_ROOT directory (e.g. tempdir)
%   owner    - GitHub repo owner (user or organization, e.g. 'mip-org'). Use '' for non-gh.
%   channel  - Channel name (e.g. 'core'). Use '' for non-gh.
%   pkgName  - Package name (e.g. 'testpkg')
%
% Optional name-value pairs:
%   'version'      - Version string (default: '1.0.0')
%   'dependencies' - Cell array of dependency names (default: {})
%   'subdirs'      - Cell array of source-relative subdirs to mkdir under
%                    the source directory (default: {}).
%   'extraPaths'   - Struct mapping group name -> cell array of
%                    source-relative paths (default: struct()). Emits a
%                    corresponding extra_paths field in mip.json.

p = inputParser;
addParameter(p, 'version', '1.0.0', @ischar);
addParameter(p, 'dependencies', {}, @iscell);
addParameter(p, 'subdirs', {}, @iscell);
addParameter(p, 'extraPaths', struct(), @isstruct);
addParameter(p, 'type', '', @ischar);
parse(p, varargin{:});

sourceType = p.Results.type;
if isempty(sourceType)
    if isempty(owner) && isempty(channel)
        error('createTestPackage:invalidArgs', ...
              'owner/channel must be given for gh packages, or pass type=''local''/''fex''.');
    end
    sourceType = 'gh';
end

if strcmp(sourceType, 'gh')
    pkgDir = fullfile(rootDir, 'packages', 'gh', owner, channel, pkgName);
else
    pkgDir = fullfile(rootDir, 'packages', sourceType, pkgName);
end

if ~exist(pkgDir, 'dir')
    mkdir(pkgDir);
end

sourceDir = fullfile(pkgDir, pkgName);
if ~exist(sourceDir, 'dir')
    mkdir(sourceDir);
end

for i = 1:numel(p.Results.subdirs)
    mkdir(fullfile(sourceDir, p.Results.subdirs{i}));
end

% Create mip.json with a "paths" field pointing at the source subdir.
mipData = struct();
mipData.name = pkgName;
mipData.version = p.Results.version;
mipData.description = ['Test package ' pkgName];
mipData.architecture = 'any';
mipData.install_type = 'test';

deps = p.Results.dependencies;
if isempty(deps)
    mipData.dependencies = reshape({}, 0, 1);
else
    mipData.dependencies = deps;
end

mipData.paths = {'.'};

extras = p.Results.extraPaths;
if ~isempty(fieldnames(extras))
    % Normalize each group's value to a cell column so jsonencode emits
    % a JSON array (matching the create_mip_json output).
    for g = fieldnames(extras)'
        v = extras.(g{1});
        if ischar(v)
            v = {v};
        end
        extras.(g{1}) = reshape(v, [], 1);
    end
    mipData.extra_paths = extras;
end

fid = fopen(fullfile(pkgDir, 'mip.json'), 'w');
fwrite(fid, jsonencode(mipData));
fclose(fid);

end
