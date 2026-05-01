function pkgInfo = read_package_json(packageDir)
%READ_PACKAGE_JSON   Read and parse a package's mip.json file.
%
% Args:
%   packageDir - Path to the package directory containing mip.json
%
% Returns:
%   pkgInfo - Struct containing package metadata with fields:
%             name, version, dependencies, etc.
%
% Example:
%   info = mip.config.read_package_json('/path/to/package');
%   fprintf('Package: %s v%s\n', info.name, info.version);

mipJsonPath = fullfile(packageDir, 'mip.json');

if ~exist(mipJsonPath, 'file')
    error('mip:mipJsonNotFound', ...
          'mip.json not found in package directory: %s', packageDir);
end

try
    % Read file contents
    jsonText = fileread(mipJsonPath);

    % Parse JSON
    pkgInfo = jsondecode(jsonText);

    % Ensure required fields exist with defaults
    if ~isfield(pkgInfo, 'name')
        error('mip:invalidMipJson', ...
              'mip.json is missing required "name" field');
    end

    if ~isfield(pkgInfo, 'version')
        pkgInfo.version = '';
    end

    if ~isfield(pkgInfo, 'dependencies')
        pkgInfo.dependencies = {};
    elseif isempty(pkgInfo.dependencies)
        pkgInfo.dependencies = {};
    elseif ~iscell(pkgInfo.dependencies)
        pkgInfo.dependencies = {pkgInfo.dependencies};
    end

    % Normalize paths field if present. The field is left absent when the
    % package has no "paths" entry in mip.json; callers treat that as a
    % malformed package and fail.
    if isfield(pkgInfo, 'paths')
        if isempty(pkgInfo.paths)
            pkgInfo.paths = {};
        elseif ~iscell(pkgInfo.paths)
            pkgInfo.paths = {pkgInfo.paths};
        end
        for i = 1:numel(pkgInfo.paths)
            mip.paths.assert_safe_relative(pkgInfo.paths{i}, ...
                sprintf('mip.json paths[%d]', i));
        end
    end

    % Normalize extra_paths field if present. Shape: struct mapping group
    % name (e.g. "examples") -> cell array of source-relative paths.
    if isfield(pkgInfo, 'extra_paths') && isstruct(pkgInfo.extra_paths)
        for key = fieldnames(pkgInfo.extra_paths)'
            if isempty(pkgInfo.extra_paths.(key{1}))
                pkgInfo.extra_paths.(key{1}) = {};
            elseif ~iscell(pkgInfo.extra_paths.(key{1}))
                pkgInfo.extra_paths.(key{1}) = {pkgInfo.extra_paths.(key{1})};
            end
            entries = pkgInfo.extra_paths.(key{1});
            for i = 1:numel(entries)
                mip.paths.assert_safe_relative(entries{i}, ...
                    sprintf('mip.json extra_paths.%s[%d]', key{1}, i));
            end
        end
    end

catch ME
    if strcmp(ME.identifier, 'mip:invalidMipJson') || ...
            strcmp(ME.identifier, 'mip:unsafePath')
        rethrow(ME);
    else
        error('mip:jsonParseFailed', ...
              'Failed to parse mip.json in %s: %s', packageDir, ME.message);
    end
end

end
