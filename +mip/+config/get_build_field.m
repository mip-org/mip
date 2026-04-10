function value = get_build_field(pkgInfo, pkgDir, fieldName)
%GET_BUILD_FIELD   Look up a build config field from mip.json or mip.yaml.
%
% First checks if the field exists in pkgInfo (from mip.json). If not,
% falls back to reading mip.yaml and resolving build configuration.
%
% Args:
%   pkgInfo   - Struct from read_package_json
%   pkgDir    - Installed package directory
%   fieldName - Field to look up (e.g. 'compile_script', 'test_script')
%
% Returns:
%   value - The field value, or '' if not found

if isfield(pkgInfo, fieldName) && ~isempty(pkgInfo.(fieldName))
    value = pkgInfo.(fieldName);
    return
end

yamlSearchDir = pkgDir;
if isfield(pkgInfo, 'source_path') && ~isempty(pkgInfo.source_path) ...
        && isfolder(pkgInfo.source_path)
    yamlSearchDir = pkgInfo.source_path;
end

mipYamlPath = fullfile(yamlSearchDir, 'mip.yaml');
if isfile(mipYamlPath)
    mipConfig = mip.config.read_mip_yaml(yamlSearchDir);
    [buildEntry, ~] = mip.build.match_build(mipConfig);
    resolvedConfig = mip.build.resolve_build_config(mipConfig, buildEntry);
    if isfield(resolvedConfig, fieldName) && ~isempty(resolvedConfig.(fieldName))
        value = resolvedConfig.(fieldName);
        return
    end
end

value = '';

end
