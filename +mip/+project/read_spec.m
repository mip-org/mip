function spec = read_spec(projectDir)
%READ_SPEC   Read a project's mip.yaml as a project spec.
%
% Usage:
%   spec = mip.project.read_spec(projectDir)
%
% mip.yaml serves as both the packaging manifest and the project spec.
% As a project spec, package identity (name/version) is optional: a
% nameless mip.yaml is a plain project spec. Compared with
% mip.config.read_mip_yaml (the package-manifest reader, which requires
% a name), this reader relaxes identity and additionally normalizes the
% project-only keys: dependency_groups (a map of named extra dependency
% lists; dev is the conventional group) and channels (extra channels
% beyond mip-org/core, consulted at lock time).
%
% Returns:
%   spec - Struct with fields:
%     name              - Package name, or '' for a nameless project spec
%     version           - Version string ('' when absent)
%     dependencies      - Cell array of dependency specs (may carry
%                         @version pins in a project spec)
%     dependency_groups - Struct: group name -> cell array of dependency specs
%     channels          - Cell array of normalized '<owner>/<channel>' specs
%     raw               - The full parsed mip.yaml struct

specPath = fullfile(projectDir, 'mip.yaml');
if ~isfile(specPath)
    error('mip:project:specNotFound', ...
          'mip.yaml not found in directory: %s', projectDir);
end

try
    yamlText = fileread(specPath);
    raw = mip.parse.parse_yaml(yamlText);
catch ME
    error('mip:yamlParseFailed', ...
          'Failed to parse mip.yaml in %s: %s', projectDir, ME.message);
end

spec = struct();
spec.raw = raw;

% Identity is optional for a project spec. When present, it must satisfy
% the same rules as a package manifest (mip.config.read_mip_yaml), so a
% named spec is simultaneously a valid package.
if isfield(raw, 'name') && ~isempty(raw.name)
    if ~ischar(raw.name)
        error('mip:invalidMipYaml', ...
              'mip.yaml "name" field must be a string. (File: %s)', specPath);
    end
    if ~mip.name.is_valid_canonical(raw.name)
        error('mip:invalidMipYaml', ...
              ['mip.yaml "name" field value "%s" is not a valid canonical ' ...
               'package name. (File: %s)'], raw.name, specPath);
    end
    spec.name = raw.name;
else
    spec.name = '';
end

if ~isfield(raw, 'version') || isempty(raw.version)
    spec.version = '';
elseif isnumeric(raw.version) && isscalar(raw.version)
    spec.version = num2str(raw.version);
elseif ischar(raw.version)
    spec.version = raw.version;
else
    error('mip:invalidMipYaml', ...
          ['mip.yaml "version" field must be a scalar string or number. ' ...
           '(File: %s)'], specPath);
end

spec.dependencies = normalize_dep_list(raw, 'dependencies', specPath, 'dependencies');

% dependency_groups: a map of named extra dependency lists.
spec.dependency_groups = struct();
if isfield(raw, 'dependency_groups') && ~isempty(raw.dependency_groups)
    if ~isstruct(raw.dependency_groups)
        error('mip:invalidMipYaml', ...
              ['mip.yaml "dependency_groups" must be a mapping of group ' ...
               'name to a list of dependencies. (File: %s)'], specPath);
    end
    groups = fieldnames(raw.dependency_groups);
    for gi = 1:numel(groups)
        g = groups{gi};
        spec.dependency_groups.(g) = normalize_dep_list( ...
            raw.dependency_groups, g, specPath, ['dependency group "' g '"']);
    end
end

% channels: extra channels beyond mip-org/core, in priority order.
spec.channels = {};
if isfield(raw, 'channels') && ~isempty(raw.channels)
    chans = raw.channels;
    if ~iscell(chans)
        chans = {chans};
    end
    for ci = 1:numel(chans)
        if ~ischar(chans{ci})
            error('mip:invalidMipYaml', ...
                  ['mip.yaml "channels" entries must be strings ' ...
                   '(''<owner>/<channel>''). (File: %s)'], specPath);
        end
        spec.channels{end+1} = mip.parse.normalize_channel_spec(chans{ci}); %#ok<AGROW>
    end
end

end

function list = normalize_dep_list(container, field, specPath, label)
% Normalize a dependency list to a row cell array of char, validating
% that every entry is a string.
    if ~isfield(container, field) || isempty(container.(field))
        list = {};
        return
    end
    list = container.(field);
    if ~iscell(list)
        list = {list};
    end
    for i = 1:numel(list)
        if ~ischar(list{i})
            error('mip:invalidMipYaml', ...
                  ['mip.yaml %s entries must be package names ' ...
                   '(strings). (File: %s)'], label, specPath);
        end
    end
    list = reshape(list, 1, []);
end
