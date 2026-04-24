function create_mip_json(outputDir, mipConfig, architecture, opts)
%CREATE_MIP_JSON   Generate mip.json metadata file.
%
% Args:
%   outputDir      - Directory to write mip.json into
%   mipConfig      - Struct from read_mip_yaml
%   architecture   - Effective architecture string
%   opts           - (Optional) Struct with fields:
%     .version     - version string to record (overrides mipConfig.version)
%     .editable    - true for editable installs
%     .source_path - original source path (for editable installs)
%     .install_type - install type string (default: 'local')

if nargin < 4
    opts = struct();
end

mipData = struct();
mipData.name = mipConfig.name;
if isfield(opts, 'version') && ~isempty(opts.version)
    mipData.version = opts.version;
else
    mipData.version = mipConfig.version;
end

if isfield(mipConfig, 'description')
    mipData.description = mipConfig.description;
else
    mipData.description = '';
end

mipData.dependencies = mipConfig.dependencies;

if isfield(opts, 'paths')
    mipData.paths = ensureCellColumn(opts.paths);
end

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

if isfield(opts, 'source_path') && ~isempty(opts.source_path)
    mipData.source_path = opts.source_path;
end

if isfield(opts, 'editable') && opts.editable
    mipData.editable = true;
end

if isfield(opts, 'compile_script') && ~isempty(opts.compile_script)
    mipData.compile_script = opts.compile_script;
end

if isfield(opts, 'test_script') && ~isempty(opts.test_script)
    mipData.test_script = opts.test_script;
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


function out = ensureCellColumn(paths)
% Normalize paths to a cell-array column so jsonencode always produces a
% JSON array (even for 0 or 1 entries).
    if isempty(paths)
        out = reshape({}, 0, 1);
    elseif ischar(paths)
        out = {paths};
    else
        out = reshape(paths, [], 1);
    end
end
