function [effectiveArch, jsonOpts] = resolve_metadata(baseDir, mipConfig, architecture)
%RESOLVE_METADATA   Derive a package's mip.json metadata from its mip.yaml.
%
% The shared mip.yaml -> mip.json derivation: match the build for the
% architecture, merge the build entry with the top-level defaults, and
% compute the resolved path lists relative to baseDir. Callers pass the
% result to mip.build.create_mip_json, adding their own fields on top
% (e.g. editable/source_path for editable installs, or the channel
% build's hash/version overrides for staged builds).
%
% Args:
%   baseDir      - Directory the path lists are computed against (the
%                  staged source copy, or the original source directory
%                  for editable installs)
%   mipConfig    - Struct from read_mip_yaml
%   architecture - (Optional) Architecture override. Default: current.
%
% Returns:
%   effectiveArch - Architecture the build was matched for
%   jsonOpts      - Struct with .paths and, when present, .extra_paths,
%                   .compile_script, and .test_script

if nargin < 3
    architecture = '';
end

[buildEntry, effectiveArch] = mip.build.match_build(mipConfig, architecture);
resolvedConfig = mip.build.resolve_build_config(mipConfig, buildEntry);

jsonOpts = struct();
jsonOpts.paths = mip.build.compute_addpaths(baseDir, resolvedConfig.paths);

extraPaths = struct();
for key = fieldnames(resolvedConfig.extra_paths)'
    extraPaths.(key{1}) = mip.build.compute_addpaths( ...
        baseDir, resolvedConfig.extra_paths.(key{1}));
end
if ~isempty(fieldnames(extraPaths))
    jsonOpts.extra_paths = extraPaths;
end

if isfield(resolvedConfig, 'compile_script') && ~isempty(resolvedConfig.compile_script)
    jsonOpts.compile_script = resolvedConfig.compile_script;
end
if isfield(resolvedConfig, 'test_script') && ~isempty(resolvedConfig.test_script)
    jsonOpts.test_script = resolvedConfig.test_script;
end

end
