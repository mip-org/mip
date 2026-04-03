function create_mip_json(outputDir, mipConfig, resolvedConfig, architecture, opts)
%CREATE_MIP_JSON   Generate mip.json metadata file.
%
% Args:
%   outputDir      - Directory to write mip.json into
%   mipConfig      - Struct from read_mip_yaml
%   resolvedConfig - Struct from resolve_build_config
%   architecture   - Effective architecture string
%   opts           - (Optional) Struct with fields:
%     .editable    - true for editable installs
%     .source_path - original source path (for editable installs)
%     .install_type - install type string (default: 'local')

if nargin < 5
    opts = struct();
end

mipData = struct();
mipData.name = mipConfig.name;
mipData.version = mipConfig.version;

if isfield(mipConfig, 'description')
    mipData.description = mipConfig.description;
else
    mipData.description = '';
end

if isfield(resolvedConfig, 'release_number')
    mipData.release_number = resolvedConfig.release_number;
else
    mipData.release_number = 1;
end

mipData.dependencies = mipConfig.dependencies;

if isfield(mipConfig, 'license')
    mipData.license = mipConfig.license;
else
    mipData.license = '';
end

if isfield(mipConfig, 'homepage')
    mipData.homepage = mipConfig.homepage;
else
    mipData.homepage = '';
end

if isfield(mipConfig, 'repository')
    mipData.repository = mipConfig.repository;
else
    mipData.repository = '';
end

mipData.architecture = architecture;

if isfield(opts, 'install_type')
    mipData.install_type = opts.install_type;
else
    mipData.install_type = 'local';
end

mipData.timestamp = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));

if isfield(opts, 'source_hash') && ~isempty(opts.source_hash)
    mipData.source_hash = opts.source_hash;
end

if isfield(opts, 'commit_hash') && ~isempty(opts.commit_hash)
    mipData.commit_hash = opts.commit_hash;
end

if isfield(opts, 'editable') && opts.editable
    mipData.editable = true;
    if isfield(opts, 'source_path')
        mipData.source_path = opts.source_path;
    end
end

jsonText = jsonencode(mipData);
mipJsonPath = fullfile(outputDir, 'mip.json');
fid = fopen(mipJsonPath, 'w');
if fid == -1
    error('mip:fileError', 'Could not create mip.json');
end
fwrite(fid, jsonText);
fclose(fid);

end
