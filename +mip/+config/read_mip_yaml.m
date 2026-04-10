function mipConfig = read_mip_yaml(packageDir)
%READ_MIP_YAML   Read and parse a package's mip.yaml file.
%
% Args:
%   packageDir - Path to the directory containing mip.yaml
%
% Returns:
%   mipConfig - Struct with fields: name, version, description,
%               dependencies, addpaths, license, homepage, repository, builds

mipYamlPath = fullfile(packageDir, 'mip.yaml');

if ~exist(mipYamlPath, 'file')
    error('mip:mipYamlNotFound', ...
          'mip.yaml not found in directory: %s', packageDir);
end

try
    fid = fopen(mipYamlPath, 'r');
    if fid == -1
        error('mip:fileError', 'Could not open file: %s', mipYamlPath);
    end
    yamlText = fread(fid, '*char')';
    fclose(fid);
    mipConfig = mip.parse.parse_yaml(yamlText);
catch ME
    error('mip:yamlParseFailed', ...
          'Failed to parse mip.yaml in %s: %s', packageDir, ME.message);
end

% Ensure required fields
if ~isfield(mipConfig, 'name')
    error('mip:invalidMipYaml', ...
          'mip.yaml is missing required "name" field');
end

if ~isfield(mipConfig, 'version')
    mipConfig.version = 'unknown';
end

% Normalize dependencies to cell array
if ~isfield(mipConfig, 'dependencies')
    mipConfig.dependencies = {};
elseif isempty(mipConfig.dependencies)
    mipConfig.dependencies = {};
elseif ~iscell(mipConfig.dependencies)
    mipConfig.dependencies = {mipConfig.dependencies};
end

% Normalize addpaths to cell array
if ~isfield(mipConfig, 'addpaths')
    mipConfig.addpaths = {};
elseif isempty(mipConfig.addpaths)
    mipConfig.addpaths = {};
elseif ~iscell(mipConfig.addpaths)
    mipConfig.addpaths = {mipConfig.addpaths};
end

% Normalize builds to cell array of structs
if ~isfield(mipConfig, 'builds')
    mipConfig.builds = {};
elseif ~iscell(mipConfig.builds)
    mipConfig.builds = num2cell(mipConfig.builds);
end
% Ensure each build entry has architectures as a cell array
for i = 1:length(mipConfig.builds)
    b = mipConfig.builds{i};
    if isfield(b, 'architectures') && ~iscell(b.architectures)
        b.architectures = {b.architectures};
        mipConfig.builds{i} = b;
    end
end

% Ensure optional string fields
if ~isfield(mipConfig, 'description')
    mipConfig.description = '';
end
if ~isfield(mipConfig, 'license')
    mipConfig.license = '';
end
if ~isfield(mipConfig, 'homepage')
    mipConfig.homepage = '';
end
if ~isfield(mipConfig, 'repository')
    mipConfig.repository = '';
end

end
