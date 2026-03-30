function config = parse_yaml(yamlPath)
%PARSE_YAML   Parse a YAML file and return a MATLAB struct.
%
% Uses MATLAB's built-in yaml.read (R2024a+) or Python's PyYAML as fallback.
%
% Args:
%   yamlPath - Path to the YAML file
%
% Returns:
%   config - MATLAB struct representing the YAML content

if ~exist(yamlPath, 'file')
    error('mip:yamlNotFound', 'YAML file not found: %s', yamlPath);
end

% Try MATLAB built-in first (R2024a+)
try
    config = yaml.read(yamlPath);
    return
catch
end

% Try Python with PyYAML
try
    yamlText = fileread(yamlPath);
    pyYaml = py.yaml.safe_load(yamlText);
    jsonStr = char(py.json.dumps(pyYaml));
    config = jsondecode(jsonStr);
    return
catch ME
    error('mip:yamlParseFailed', ...
        ['Failed to parse YAML file: %s\n' ...
         'Install PyYAML (pip install pyyaml) or use MATLAB R2024a+.\n' ...
         'Error: %s'], yamlPath, ME.message);
end

end
