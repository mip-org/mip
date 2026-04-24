function mipConfig = read_mip_yaml(packageDir)
%READ_MIP_YAML   Read and parse a package's mip.yaml file.
%
% Args:
%   packageDir - Path to the directory containing mip.yaml
%
% Returns:
%   mipConfig - Struct with fields: name, version, description,
%               dependencies, paths, extra_paths, license, homepage,
%               repository, builds

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

if ~isfield(mipConfig, 'version') || isempty(mipConfig.version)
    mipConfig.version = '';
end

% Normalize dependencies to cell array
if ~isfield(mipConfig, 'dependencies')
    mipConfig.dependencies = {};
elseif isempty(mipConfig.dependencies)
    mipConfig.dependencies = {};
elseif ~iscell(mipConfig.dependencies)
    mipConfig.dependencies = {mipConfig.dependencies};
end

% Normalize paths to cell array
if ~isfield(mipConfig, 'paths')
    mipConfig.paths = {};
elseif isempty(mipConfig.paths)
    mipConfig.paths = {};
elseif ~iscell(mipConfig.paths)
    mipConfig.paths = {mipConfig.paths};
end

% Normalize extra_paths: a mapping of group name -> list of path entries
% (same shape as top-level paths). Each group's list is normalized to a
% cell array.
if ~isfield(mipConfig, 'extra_paths') || isempty(mipConfig.extra_paths)
    mipConfig.extra_paths = struct();
elseif ~isstruct(mipConfig.extra_paths)
    error('mip:invalidMipYaml', ...
          ['extra_paths must be a mapping of group name to list of path ' ...
           'entries (e.g. extra_paths.examples).']);
else
    groups = fieldnames(mipConfig.extra_paths);
    for gi = 1:length(groups)
        key = groups{gi};
        val = mipConfig.extra_paths.(key);
        if isempty(val)
            mipConfig.extra_paths.(key) = {};
        elseif ~iscell(val)
            mipConfig.extra_paths.(key) = {val};
        end
    end
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
