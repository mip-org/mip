function spec = read_spec(projectDir)
%READ_SPEC   Read and normalize a project's mipenv.yaml.
%
% Args:
%   projectDir - Project directory (from mip.env.project_dir).
%
% Returns:
%   spec - Struct with fields:
%            name         - char, project name ('' if unset)
%            dependencies - cell array of package specs (bare names or FQNs,
%                           optionally with @version)
%            channels     - cell array of channel specs consulted (in
%                           priority order) for bare-name resolution, in
%                           addition to the always-present mip-org/core
%
% The spec is the hand-authored input to the environment (the analog of
% uv's pyproject.toml). It is deliberately small: what to install and where
% to look for it. Exact resolved versions live in mipenv.lock, not here.

specFile = mip.env.spec_path(projectDir);
if ~exist(specFile, 'file')
    error('mip:env:noSpec', ...
          ['No mipenv.yaml found in "%s".\n' ...
           'Run "mip env init" to create one.'], projectDir);
end

fid = fopen(specFile, 'r');
if fid == -1
    error('mip:env:specReadFailed', 'Could not open %s', specFile);
end
cleaner = onCleanup(@() fclose(fid));
text = fread(fid, '*char')';

try
    raw = mip.parse.parse_yaml(text);
catch ME
    error('mip:env:specParseFailed', ...
          'Failed to parse %s: %s', specFile, ME.message);
end

spec = struct('name', '', 'dependencies', {{}}, 'channels', {{}});

if isfield(raw, 'name') && ~isempty(raw.name) && ischar(raw.name)
    spec.name = raw.name;
end

spec.dependencies = normalize_list(raw, 'dependencies');
spec.channels = normalize_list(raw, 'channels');

end

function items = normalize_list(raw, field)
% Coerce a YAML scalar/sequence field into a cell array of char rows.
items = {};
if ~isfield(raw, field) || isempty(raw.(field))
    return
end
val = raw.(field);
if ~iscell(val)
    val = {val};
end
for i = 1:numel(val)
    item = val{i};
    if isstring(item)
        item = char(item);
    end
    if ischar(item) && ~isempty(strtrim(item))
        items{end+1} = strtrim(item); %#ok<AGROW>
    end
end
end
